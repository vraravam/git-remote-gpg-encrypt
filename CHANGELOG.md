# Changelog

## 0.1.0

### Initial extraction as a standalone tool

Extracted from a personal dotfiles repository's `EncryptedBackup`
module/`git-remote-encrypted-backup` helper into a standalone, general-purpose tool,
fully decoupled from any dotfiles-specific infrastructure.

- `lib/git_remote_gpg_encrypt/` -- core library: `Core`, `Config`, `PassphraseStore`,
  `Encryptor`, `Chunker`, `ShellGit`, `WrapperRepo`, `Backup`, `RemoteHelper`.
- `bin/git-remote-gpg-encrypt` -- the git remote-helper entrypoint (`fetch`/`push`/
  `option` capabilities per `gitremote-helpers(7)`), dispatched by git for any
  `gpg-encrypt::<url>` remote.
- `bin/git-gpg-encrypt-setup` -- one-time readiness check (gpg installed + passphrase
  configured).
- `bin/git-gpg-encrypt-verify` -- verifies the current backup still decrypts and passes
  `git bundle verify`.
- `bin/git-gpg-encrypt-restore` -- disaster-recovery / fresh-machine bootstrap (clone +
  decrypt + checkout into a target directory, safe on a pre-existing non-empty one).
- Full RSpec suite (`spec/`) including an end-to-end test that exercises the actual
  remote-helper protocol via real `git push`/`git fetch` subprocesses.
- Design changes from the original dotfiles implementation:
  - The wrapper-repo address is now a full git URL (`gpg-encrypt::<any-git-url>`)
    instead of a bare repo name resolved via a separately-configured GitHub username --
    works with any git host, not just GitHub under one specific account.
  - `age` was evaluated as a replacement for `gpg --symmetric` and rejected: its
    passphrase mode has no non-interactive input mechanism (see `docs/DESIGN.md`).
  - No dependency on any structured/colored logging framework, `EnvVars`, `GitProcessor`,
    or `CliParser` infrastructure -- plain `warn`/`puts`, a single `Config` module, and a
    minimal `ShellGit` wrapper around plain git plumbing (no reliance on the adopter's
    own git aliases or third-party git tools).
  - Chunk padding widened from 3 to 4 digits (up to 10,000 chunks instead of 1,000).
  - `Encryptor` adds `--pinentry-mode loopback` and a configurable `--s2k-count`
    (defaults to GnuPG's own maximum) on top of the original's `--batch
    --passphrase-fd 0` mechanism.

### CI reliability and legacy-chunk cleanup fixes

Fixes discovered while migrating a real dotfiles installation from the original
embedded `EncryptedBackup` module over to this standalone tool, and while
diagnosing an intermittent CI failure.

- `spec/end_to_end_spec.rb` -- CI providers (including GitHub Actions) set
  `GIT_PROTOCOL_FROM_USER=0` job-wide as a hardening measure against untrusted
  nested/recursive git operations (see git's CVE-2022-39253 remediation). That
  variable propagated into the test's `git push`/`git fetch` subprocesses and made
  git reject our own `gpg-encrypt::` transport with `fatal: transport 'gpg-encrypt'
  not allowed`, even though the same command works fine interactively. The test's
  `env` hash now forces `GIT_PROTOCOL_FROM_USER=1` to represent genuine direct user
  usage. `README.md` documents the same caveat for anyone using this remote from
  their own CI/CD pipeline.
- `lib/git_remote_gpg_encrypt/chunker.rb` -- `_remove_existing` only ever globbed
  the current `PAD_WIDTH` (4 digits), so chunk files written by any earlier
  zero-padding width -- e.g. the original embedded tool's 3-digit
  (`backup.gpg.000`) convention -- were never matched, never staged for deletion,
  and lingered forever alongside each new push's chunks. `_remove_existing` now
  matches `<basename>.<digits>` generically (any number of digits), so stale
  chunks from any past width are always cleaned up without needing to enumerate
  which widths those were.
- `lib/git_remote_gpg_encrypt/encryptor.rb` -- a cold `gpg-agent` (its very first
  invocation on a machine/CI runner where it has never run before) can occasionally
  lose a startup/socket-binding race and fail transiently on the first call --
  confirmed as the cause of an intermittent CI failure (3 of 4 runs on the
  identical commit passed) that did not reproduce locally, where `gpg-agent` is
  already warm from prior use. `_run_gpg` now retries up to `MAX_ATTEMPTS` (3)
  times with a short delay, which only smooths over this one class of transient
  infrastructure hiccup -- a genuine wrong-passphrase or corrupted-input failure
  still fails identically on every attempt.
