# Changelog

---

### 0.2.0

#### Add a Nix flake as an additional installation channel

- `flake.nix` -- added: packages `bin/` + `lib/` as an installable Nix flake (`packages.<system>.default`, `apps.<system>.default`), alongside the existing Homebrew tap and curl/manual install methods. Restricts `src` to `bin/`+`lib/` via `lib.fileset` so unrelated file changes (docs, specs) don't invalidate the build; wraps all four `bin/` executables with `git` and `gnupg` on `PATH` via `makeWrapper`, mirroring the Homebrew formula's `depends_on`. Intentionally does not patch the `#!/usr/bin/env ruby` shebangs -- targets whatever system Ruby is first on `PATH` at runtime, consistent with this repo's `Gemfile`/`.mise.toml` pinning to system Ruby.
- `README.md` -- added a "Nix flake" subsection under Installation documenting `nix profile install`/`nix run`, and how to reference this repo's `packages.${system}.default` output as an input from another flake (e.g. a home-manager/nix-darwin config).
- `.gitignore` -- ignore `/result` and `/result-*` (Nix build-output symlinks).

#### Adopting these changes

- No action needed for existing Homebrew/curl/manual installs -- this is purely an additional installation channel.
- Nix users can install via `nix profile install github:vraravam/git-remote-gpg-encrypt`, run it directly via `nix run`, or depend on it as a flake input.

---

### 0.1.2

#### Split opencode's AI instructions into on-demand skills and a trimmed always-on core

- `.opencode/opencode.json` -- added (didn't exist before): the same git-state-modifying `permission.bash` deny-list as the dotfiles repo (`git commit`, `git push`, `git rebase`, etc.), and an `instructions` array limited to `.ai/instructions.md` plus the four cross-cutting domains (`whitespace-rules.md`, `edit-checklist.md`, `character-encoding.md`, `comment-philosophy.md`).
- `.opencode/skills/gpg-encrypt-ruby-scripting/SKILL.md`, `.opencode/skills/gpg-encrypt-changelog-maintenance/SKILL.md` -- added, each a symlink into `.ai/domains/ruby-scripting.md` and `.ai/domains/changelog-maintenance.md` respectively (not a copy), now loaded on-demand by opencode instead of never being loaded automatically at all (no `opencode.json` existed here before).
- `.ai/domains/ruby-scripting.md`, `.ai/domains/changelog-maintenance.md` -- added the `name`/`description` frontmatter keys backing the two skills above, alongside the existing `applyTo` key still used by Copilot/Cursor/Windsurf.
- `AGENTS.md` -- added an "OpenCode-Specific Notes" section documenting the always-on/on-demand split and the enforced git-state permission deny-list.

#### Adopting these changes

- Restart opencode (or any running session) to pick up the new `.opencode/opencode.json`, skills, and `AGENTS.md` notes.
- No functional code changed -- this is AI-assistant tooling configuration only.

---

### 0.1.1

#### Complete RSpec line coverage to 100%

- Added `spec/core_spec.rb`, `spec/config_spec.rb`, `spec/passphrase_store_spec.rb`, and
  `spec/remote_helper_spec.rb` -- previously-untested modules (`Core`, `Config`,
  `PassphraseStore`, `RemoteHelper`) now have full unit coverage, including
  `RemoteHelper`'s protocol dispatch, `_with_stdout_redirected`'s real fd-level
  redirect, and `PassphraseStore`'s macOS Keychain / non-interactive failure paths.
- `spec/backup_spec.rb`, `spec/wrapper_repo_spec.rb`, `spec/shell_git_spec.rb` -- added
  targeted specs for previously-uncovered failure branches (`git bundle create`/decrypt/
  chunk/list-heads/unbundle failures in `Backup`, `WrapperRepo.commit_and_push`'s commit
  failure, `WrapperRepo`'s remote-default-branch-rename self-heal, and
  `ShellGit#rename_branch`/`#set_upstream`).
- `spec/spec_helper.rb` -- added an `IOHelpers` module (`with_stdin`, `capture_stdout`)
  for specs that exercise real stdin/stdout plumbing, since RSpec's own
  `output(...).to_stdout` matcher can't observe `RemoteHelper`'s real fd-level
  `IO#reopen` redirect.
- Line coverage raised from 74% to 100% (428/428 lines); test count from 31 to 96
  examples.

#### Fix missing YARD @return tags in RemoteHelper

- `lib/git_remote_gpg_encrypt/remote_helper.rb` -- `_reply_option`, `_reply_list`,
  `_consume_fetch_batch`, and `_reply_push` now document `@return [void]`, matching the
  convention already established by `_reply_capabilities` for the same
  "protocol-reply, no return value" method shape.

#### Add Dependabot and a scheduled system-Ruby-version-drift check

- `.github/dependabot.yml` -- weekly `bundler` ecosystem updates for this repo's
  dev-tooling gems (`rspec`, `simplecov`, `rubocop`, `rubocop-ast`, `bundler-audit`).
- `.github/workflows/dependabot-audit.yml` -- runs `bundler-audit` against Dependabot's
  own PRs and requests a Copilot code review, guided by the new
  `.github/instructions/dependabot-security-review.instructions.md` checklist.
- `.github/workflows/system-ruby-version-check.yml` and
  `.github/scripts/check-system-ruby-version.sh` -- weekly scheduled check (plus
  `workflow_dispatch`) that compares the macOS runner's system Ruby against the
  `Gemfile`'s `ruby '2.6.10'` pin and files a tracking issue on drift; a bash port of
  the equivalent dotfiles script (this repo has no zsh).

#### Establish CHANGELOG.md maintenance conventions

- `.ai/domains/changelog-maintenance.md` -- new domain file (adapted from the dotfiles
  repository's changelog generation rules): mandatory one-entry-per-commit rule, entry
  structure/grouping conventions, amend/squash rewrite rules, and a GitHub Release
  mirroring step for this repo's Homebrew-tap distribution model. Registered in
  `.ai/instructions.md`'s domain table and `AGENTS.md`.
- `CHANGELOG.md` -- reformatted the existing `0.1.0` entry to the newly-established
  `### X.Y.Z` / `#### theme` / `---`-separator structure.
- `README.md` -- added a `## Changelog` section linking to `CHANGELOG.md` and this
  repo's GitHub Releases page.

---

### 0.1.0

#### Initial extraction as a standalone tool

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

#### CI reliability and legacy-chunk cleanup fixes

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

---
