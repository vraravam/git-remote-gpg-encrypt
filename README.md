# git-remote-gpg-encrypt

> Transparent, passphrase-only, whole-history encrypted git backups -- via a real git
> remote, so `git push`/`git pull`/`git fetch` just works!

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/Ruby-2.6%2B-red?logo=ruby)](https://www.ruby-lang.org/)
[![macOS](https://img.shields.io/badge/macOS-11%2B-blue?logo=apple)](https://www.apple.com/macos/)

[![Lint](https://github.com/vraravam/git-remote-gpg-encrypt/actions/workflows/lint.yml/badge.svg)](https://github.com/vraravam/git-remote-gpg-encrypt/actions/workflows/lint.yml)
[![RSpec](https://github.com/vraravam/git-remote-gpg-encrypt/actions/workflows/rspec.yml/badge.svg)](https://github.com/vraravam/git-remote-gpg-encrypt/actions/workflows/rspec.yml)
[![codecov](https://codecov.io/gh/vraravam/git-remote-gpg-encrypt/branch/master/graph/badge.svg)](https://codecov.io/gh/vraravam/git-remote-gpg-encrypt)
[![Bundler Audit](https://github.com/vraravam/git-remote-gpg-encrypt/actions/workflows/bundler-audit.yml/badge.svg)](https://github.com/vraravam/git-remote-gpg-encrypt/actions/workflows/bundler-audit.yml)

## What is this?

A [git remote helper](https://git-scm.com/docs/gitremote-helpers) that transparently
backs up a repository's **entire history** -- not just its current files, all of it --
as a single `gpg --symmetric`-encrypted blob, chunked to fit under GitHub's file-size
limits, and pushed to a plain, unencrypted wrapper repo on any git host.

```sh
git remote add backup gpg-encrypt::https://github.com/YOU/my-backup-repo.git
git push backup main     # bundles + encrypts + chunks + pushes -- transparently
git pull backup          # fetches + decrypts + unbundles -- transparently
```

`backup` is just an example name -- see [Usage](#usage) below for using it as an
additional remote alongside `origin`, or as `origin` itself.

That's the whole interface. No wrapper scripts, no manual encrypt/decrypt steps, no
separate backup tool to remember to run -- once the remote is configured, plain git
commands do the work.

## Why does this exist? (the research that led here)

Before writing a line of code, I looked for an existing tool that already does this.
None of the ones I found satisfy all of the following at once:

1. **Encrypts the whole repository** (history, file names, tree structure) -- not just
   individual file contents.
2. **Purely passphrase-based** -- no keypair or key file that has to be backed up
   somewhere else first (which just relocates the "how do I recover this" problem from
   the backup to the key).
3. **Fully non-interactive** -- has to work from a plain `git push`/`git pull`, and from
   cron, with zero prompts.
4. **Minimal, auditable dependency footprint.**

| Tool | Whole-repo | Passphrase-only | Non-interactive | Notes |
|---|---|---|---|---|
| [git-crypt](https://github.com/AGWA/git-crypt) | No (per-file filter) | No (GPG keys or an exported key file) | Yes | Its own README says: *"For encrypting an entire repository, consider... git-remote-gcrypt instead"* |
| [transcrypt](https://github.com/elasticdog/transcrypt) | No (per-file filter) | Yes | Yes | Its own README says: *"There are much better options if your goal is to encrypt the entire repository"* |
| [git-remote-gcrypt](https://github.com/spwhitton/git-remote-gcrypt) | Yes | **No** -- encrypts to your own GPG keypair by default | Yes | The keypair itself becomes something you must separately back up |
| [git-remote-sealed](https://github.com/hibariya/git-remote-sealed) | Yes | **No** -- `age` identity file per device, enroll/revoke model | Yes | Closest architectural match; well-engineered (Quint-modeled protocol), but still keyfile-based |
| **git-remote-gpg-encrypt** (this tool) | **Yes** | **Yes** | **Yes** | `gpg --symmetric` + `git bundle`, chunked for hosting-limit compatibility |

I also specifically evaluated [age](https://github.com/FiloSottile/age) as a modern
replacement for `gpg --symmetric` (better default KDF -- scrypt is memory-hard, more
brute-force-resistant than GnuPG's iterated-hash S2K; smaller, simpler, single static
binary). It's disqualified for this specific use case: `age`'s passphrase mode
(`age -p`) has **no non-interactive input mechanism at all** -- I traced this into its
Go source (`internal/term/term.go`'s `WithTerminal`, which opens `/dev/tty` directly and
refuses to read a passphrase from stdin, confirmed by the still-open
[FiloSottile/age#603](https://github.com/FiloSottile/age/issues/603)). That's a
deliberate design choice by `age`'s author, and a reasonable one for `age`'s typical use
cases -- but it means every single `git push`/`git pull` would require a human at a live
terminal, which defeats the entire point of a *transparent* backup remote. GnuPG's
`--batch --passphrase-fd 0` is a long-stable, intentional feature built for exactly this
kind of scripted use, which is why it's the mechanism this tool relies on.

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full write-up, including why chunking is
necessary at all (GitHub's 100MB hard limit and 50MB warning threshold) and the
`git bundle` + wrapper-repo mechanics.

## Installation

### Homebrew

```sh
brew tap vraravam/tap
brew install git-remote-gpg-encrypt
```

Installs `git`, `gnupg`, and this tool's four `bin/` executables, all wired up on
`PATH`. See the [tap repo](https://github.com/vraravam/homebrew-tap)
for the formula itself.

### curl (any macOS or Linux machine with `git`, `gpg`, and `ruby` >= 2.6)

```sh
curl -fsSL https://raw.githubusercontent.com/vraravam/git-remote-gpg-encrypt/master/install.sh | bash
```

This clones the repo to `~/.local/share/git-remote-gpg-encrypt` and symlinks the four
`bin/` executables into `~/.local/bin` (override both locations with
`GIT_GPG_ENCRYPT_HOME`/`GIT_GPG_ENCRYPT_BIN_DIR`). Make sure `~/.local/bin` is on your
`PATH`.

### Manual

```sh
git clone https://github.com/vraravam/git-remote-gpg-encrypt.git
mkdir -p ~/.local/bin/
ln -s "$(pwd)/git-remote-gpg-encrypt/bin/"* ~/.local/bin/
```

## Requirements

- `git` (any reasonably recent version)
- [GnuPG](https://gnupg.org/) (`gpg` on `PATH` -- `brew install gnupg` on macOS,
  `apt install gnupg`/`dnf install gnupg2` on Linux)
- Ruby >= 2.6 (ships by default on macOS; `apt install ruby`/`dnf install ruby` on Linux)
- On macOS: the passphrase is stored in the Keychain. On any platform (including for
  testing): the `GIT_GPG_ENCRYPT_PASSPHRASE` environment variable always takes
  precedence over the Keychain.

## One-time setup

```sh
git gpg-encrypt-setup
```

Verifies `gpg` is installed and, if no passphrase is configured yet, prompts you to
store one (macOS: in the Keychain, via `security add-generic-password`'s own masked,
double-entry prompt -- the passphrase never touches this tool's process memory or
command-line arguments). Safe to run repeatedly; does nothing visible once configured.

Non-macOS or non-interactive setup:

```sh
export GIT_GPG_ENCRYPT_PASSPHRASE='a strong passphrase from your password manager'
```

## Usage

**1. Create an empty, plain (unencrypted) repository** on any git host to serve as the
wrapper -- e.g. a new empty GitHub repo. This will hold nothing but encrypted, chunked
blobs; its contents are meaningless without your passphrase, but its *existence* and
*commit history length* are visible to whoever hosts it -- see
[Security Model](#security-model).

**2. Add it as a remote**, using the `gpg-encrypt::` prefix in front of the wrapper
repo's normal URL. The remote's name is entirely up to you -- this tool has no opinion
on it and no code path that varies based on it (see
[`docs/DESIGN.md`](docs/DESIGN.md#remote-naming-is-entirely-outside-this-tools-purview)):
add it as `backup` alongside your normal plaintext `origin` (the most common setup), or
use `origin` itself if you want the encrypted remote to *be* your primary one. Either
way, git resolves the name to this tool before ever invoking it -- this tool only ever
sees the URL.

```sh
cd your-repo

# Most common: an additional remote alongside a plaintext 'origin'
git remote add backup gpg-encrypt::https://github.com/YOU/my-backup-repo.git

# Equally valid: replace 'origin' outright
git remote add origin gpg-encrypt::https://github.com/YOU/my-backup-repo.git
```

**3. Push and pull like any other remote** (using whichever name you chose above):

```sh
git push backup main
git pull backup
git fetch backup
```

### Disaster recovery / fresh-machine restore

```sh
git gpg-encrypt-restore https://github.com/YOU/my-backup-repo.git ~/restored-repo
```

Clones the wrapper repo, decrypts the latest backup, and checks it out into
`~/restored-repo` (created if missing; safe to use on an existing non-empty directory
too -- e.g. restoring straight into `$HOME`).

### Verify a backup before doing anything destructive

```sh
git gpg-encrypt-verify https://github.com/YOU/my-backup-repo.git
```

Confirms the current backup decrypts with your configured passphrase and passes
`git bundle verify`. Run this before squashing or force-pushing the wrapper repo's own
history.

### Using this remote helper in CI or other automated contexts

Modern git only allows custom remote-helper protocols (anything requiring a
`git-remote-<scheme>` helper, like this tool's own `gpg-encrypt::`) when the operation
is considered "user-initiated". Many CI providers -- including GitHub Actions -- set
`GIT_PROTOCOL_FROM_USER=0` job-wide as a hardening measure against untrusted
nested/recursive git operations (see git's CVE-2022-39253 remediation). That variable
propagates into every subprocess the job spawns, so a plain `git push backup main` in
such an environment fails with `fatal: transport 'gpg-encrypt' not allowed` even though
the exact same command works fine on an interactive machine.

If you need to push/fetch through a `gpg-encrypt::` remote from CI or another
automated, non-interactive context, explicitly set `GIT_PROTOCOL_FROM_USER=1` for that
step:

```sh
GIT_PROTOCOL_FROM_USER=1 git push backup main
```

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `GIT_GPG_ENCRYPT_PASSPHRASE` | (none) | Passphrase, takes precedence over the macOS Keychain. Required on non-macOS. |
| `GIT_GPG_ENCRYPT_KEYCHAIN_SERVICE` | `git-remote-gpg-encrypt` | macOS Keychain service name |
| `GIT_GPG_ENCRYPT_CHUNK_SIZE_BYTES` | `47185920` (45MB) | Chunk size; default stays under GitHub's 50MB warning threshold and 100MB hard limit |
| `GIT_GPG_ENCRYPT_S2K_COUNT` | `65011712` (gpg's max) | GnuPG passphrase-derivation iteration count |
| `XDG_CACHE_HOME` | `~/.cache` | Base directory for local wrapper-repo mirror clones |

## Security Model

- **What's protected**: file contents, file names, directory structure, commit
  messages, and full commit history -- all of it lives only inside the encrypted blob.
- **What's visible to whoever hosts the wrapper repo**: that the repo exists, roughly
  how large the encrypted blob is (via chunk count/size), and how often it's pushed to.
  This is a real trade-off versus a fully private host -- accepted here in exchange for
  being usable with any plain, free, public git host.
- **Passphrase storage**: macOS Keychain (`security add-generic-password -A`, readable
  non-interactively) or the `GIT_GPG_ENCRYPT_PASSPHRASE` environment variable. Never
  stored in either repo.
- **No key rotation**: like `git-crypt`/`transcrypt`, if you need to change the
  passphrase, old history remains decryptable with the old one until you rewrite the
  wrapper repo's history entirely (`git gpg-encrypt-verify` first!).
- **Every push replaces the whole backup** (no incremental/delta backup) -- there's no
  server-side "reject non-fast-forward" check the way a real git server enforces for
  plaintext pushes. Fetch/pull before pushing, as always.

## Development

```sh
git clone https://github.com/vraravam/git-remote-gpg-encrypt.git
cd git-remote-gpg-encrypt
bundle install
bundle exec rspec      # full test suite (exercises real gpg/git subprocesses)
bundle exec rubocop    # lint
```

See [`.ai/instructions.md`](.ai/instructions.md) for the full coding conventions used
throughout this repository.

## License

[MIT](LICENSE)
