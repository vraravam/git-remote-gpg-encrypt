# Design Rationale

## The problem

You want your git repository's full history backed up somewhere off your machine, in a
way that:

1. Survives losing the machine entirely (so the backup can't depend on a secret that
   only lives on that same machine, with no independent copy).
2. Doesn't require paying for or trusting a specialized encrypted-hosting service.
3. Doesn't leak the repository's contents, file names, or structure to whoever hosts the
   backup.
4. Works transparently with plain `git` commands, not a separate backup tool you have to
   remember to run.

## Why not an existing tool?

See the comparison table in [`README.md`](../README.md#why-does-this-exist-the-research-that-led-here).
Short version: every whole-repository encryption tool found (`git-remote-gcrypt`,
`git-remote-sealed`) requires a keypair/identity file, which just relocates the "what do
I back this up with" problem from the repository to the key. Every purely
passphrase-based tool found (`git-crypt`, `transcrypt`) only encrypts individual file
contents via a git clean/smudge filter -- their own authors recommend against using them
for whole-repository encryption, and neither hides file names or tree structure.

## Why `age` was rejected as the crypto backend

`age -p` (passphrase mode) is cryptographically well-designed -- scrypt KDF (memory-hard,
more resistant to hardware-accelerated brute force than GnuPG's default iterated-hash
S2K) and ChaCha20-Poly1305 AEAD in a modern STREAM construction, specified at
[age-encryption.org/v1](https://age-encryption.org/v1) (a C2SP specification).

But its CLI has **no way to supply a passphrase non-interactively**. Tracing this into
the actual Go source (not just the docs):

- `cmd/age/age.go`'s `-p` handling calls `passphrasePromptForEncryption`/
  `passphrasePromptForDecryption` unconditionally.
- Both call `term.ReadSecret()`, which calls `internal/term/term.go`'s `WithTerminal()`.
- `WithTerminal()` opens `/dev/tty` **directly** -- bypassing stdin redirection entirely
  -- and if `/dev/tty` isn't available, returns a hard error: `"standard input is not a
  terminal, and /dev/tty is not available"`.
- [FiloSottile/age#603](https://github.com/FiloSottile/age/issues/603) ("can't pass
  password via stdin during decrypt") confirms this is a known, deliberate design
  choice, not an oversight -- it's core to `age`'s misuse-resistant philosophy ("no
  config options").

This is disqualifying for a git remote helper: `bundle_and_push`/
`fetch_and_list_bundle_refs` must run completely unattended, invoked transparently by a
plain `git push`/`git pull`/`git fetch` (and potentially cron). `age -p` would require a
human at a live terminal on every single push and pull.

The workarounds all have worse trade-offs than just using `gpg --symmetric`:
- Switch to `age -r/-i` keypair mode -- reintroduces the exact "key to back up
  separately" problem this project exists to avoid.
- Ship a compiled Go helper against the `age` *library* (which has no such restriction)
  -- adds a second language/toolchain to what's meant to be a small, auditable,
  dependency-light Ruby tool.
- Reimplement the scrypt+ChaCha20-Poly1305 format in Ruby -- a "don't roll your own
  crypto" anti-pattern for a security tool.

GnuPG's `--batch --passphrase-fd 0` is a decades-stable, intentional feature built
specifically for non-interactive/scripted use -- exactly what this tool needs. That's
why `gpg --symmetric` is the backend, not a compromise.

## Why chunking is necessary

GitHub (and most git hosts) hard-reject any single pushed file over 100MB. A full-history
bundle of a real repository -- especially one with binary assets, scanned documents, or
just years of accumulated history -- routinely exceeds that. There is also a separate,
non-fatal 50MB *recommended* threshold: files between 50-100MB still push successfully,
but trigger a `GH001: Large files detected... this is larger than GitHub's recommended
maximum file size of 50.00 MB` warning on every single push, which reads exactly like a
failure even though it isn't one.

The default chunk size (45MB, see `Config.chunk_size_bytes`) stays comfortably under
both thresholds. Chunks are named `backup.gpg.0000`, `backup.gpg.0001`, etc. -- zero-
padded to 4 digits (10,000 chunks at the default size = ~450GB, far beyond any realistic
use case).

## Why the wrapper repo is a separate, plain repo

The encrypted backup lives in its own local mirror clone (`WrapperRepo`, cached under
`XDG_CACHE_HOME`), distinct from the repository actually being backed up. This
deliberately decouples "the live, plaintext, local repository" from "the encrypted
backup" -- the backup is a wholesale content replacement on every push (bundle -> encrypt
-> chunk -> commit -> push), which would make no sense as commits directly inside the
repository being backed up.

## Remote naming is entirely outside this tool's purview

Whether a `gpg-encrypt::<url>` remote is added as an additional remote (`backup`,
alongside a plaintext `origin`) or as a wholesale replacement for `origin` itself is a
decision this tool has no opinion on and no code path that varies based on:

- `bin/git-remote-gpg-encrypt` (the remote-helper entrypoint) reads only `ARGV[-1]`
  (the URL, per `gitremote-helpers(7)` INVOCATION) and `GIT_DIR` from the environment.
  It never inspects `ARGV[0]` (the remote's configured name) -- git resolves "which
  remote is this" entirely upstream, before ever invoking the helper.
- `Backup.bundle_and_push`/`Backup.fetch_and_list_bundle_refs` take a `git_dir:` and a
  `remote_url:` -- both call `git bundle create --all`/`git bundle unbundle`, neither of
  which has any concept of "which remote" at all.
- The only `'origin'` references anywhere in `lib/` (`ShellGit`/`WrapperRepo`) refer
  exclusively to the tool's *own* internal wrapper-repo mirror clone (a plain
  `git clone` always names its remote `origin` by default) -- a completely separate,
  cache-directory-local implementation detail, unrelated to how the user's own
  repository names its remotes.

Use whichever name and topology fits your workflow -- an additional `backup` remote
next to a normal `origin`, or `origin` itself pointed straight at `gpg-encrypt::<url>`.

## Git remote-helper protocol

`bin/git-remote-gpg-encrypt` implements the `fetch`/`push`/`option` capabilities from
[`gitremote-helpers(7)`](https://git-scm.com/docs/gitremote-helpers). Summary:

- `capabilities` -> advertises `fetch`, `push`, `option`.
- `list`/`list for-push` -> fetches + decrypts the latest backup, imports its objects
  into the local repo's object database, and reports the ref list it contains. Since
  decryption is all-or-nothing, this eagerly imports everything up front on every
  `list` -- there's no cheaper way to answer it partially.
- `fetch <sha1> <name>` -> objects are already present from `list`; just acknowledges
  the batch (per the `fetch` capability's semantics: the helper populates the object
  database, git itself updates remote-tracking refs from `list`'s output).
- `push +<src>:<dst>` -> bundles **all** local refs (not just the ones in this push --
  matches the whole-repo backup design) and pushes the result.

A known limitation shared with `git-remote-gcrypt`: every push replaces the entire
backup, so there's no server-side non-fast-forward rejection the way a real git server
provides for plaintext pushes. Git's own pre-push fast-forward check (based on this
helper's `list for-push` output) still applies.

### Why stdout redirection matters

The wire protocol above is carried entirely over the remote helper's stdout/stdin. Any
of `Backup`'s subprocess calls (git bundle/clone/push/pull) inherit this process's real
stdout file descriptor -- if any of them write to it, they corrupt the protocol stream.
`RemoteHelper._with_stdout_redirected` uses `IO#reopen` (a real `dup2()`-level redirect,
not just reassigning Ruby's `$stdout` object) specifically because a subprocess writing
to its inherited fd 1 would otherwise bypass a mere Ruby-level `$stdout` reassignment
entirely.
