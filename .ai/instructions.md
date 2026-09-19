# git-remote-gpg-encrypt -- AI Assistant Instructions

This is the main entry point for any AI coding assistant working on this repository.
Domain-specific rules are in [`domains/`](./domains/).

## Instruction Files

| Domain | File | Coverage |
|--------|------|----------|
| Ruby scripting | [`domains/ruby-scripting.md`](./domains/ruby-scripting.md) | All `.rb` files and `bin/*` executables |
| Comment philosophy | [`domains/comment-philosophy.md`](./domains/comment-philosophy.md) | Comment style/rationale |
| Character encoding | [`domains/character-encoding.md`](./domains/character-encoding.md) | ASCII-only requirement |
| Whitespace rules | [`domains/whitespace-rules.md`](./domains/whitespace-rules.md) | Post-edit whitespace checks |
| Edit checklist | [`domains/edit-checklist.md`](./domains/edit-checklist.md) | Full post-edit workflow |

**DO NOT duplicate content from these files elsewhere -- they are the authoritative
source.**

These files were adapted from the [dotfiles repository](https://github.com/vraravam/dotfiles)'s
own `.ai/` instruction set, trimmed to what actually applies to this much smaller,
deliberately dependency-light project (no `Logging`/`EnvVars`/`GitProcessor`/`CliParser`
infrastructure here -- see `domains/ruby-scripting.md`'s header for specifics).

## Project Summary

A git remote helper (`gpg-encrypt::<url>`) that transparently backs up a repository's
full history as a `gpg --symmetric`-encrypted, chunked `git bundle`, pushed to a plain
wrapper repo on any git host. See `README.md` for the full design rationale (including
why `age`, `git-crypt`, `git-remote-gcrypt`, and `git-remote-sealed` were each
considered and rejected as alternatives).

```
lib/git_remote_gpg_encrypt/
  core.rb            - dependency-free helpers (nil_or_empty?, tty_available?, ...)
  config.rb           - all environment-variable-driven settings, in one place
  passphrase_store.rb - macOS Keychain / GIT_GPG_ENCRYPT_PASSPHRASE lookup
  encryptor.rb        - gpg --symmetric encrypt/decrypt
  chunker.rb          - pure-Ruby split/join for GitHub's 100MB file-size limit
  shell_git.rb        - minimal git plumbing wrapper (no aliases, no git-extras)
  wrapper_repo.rb      - manages the local mirror of the remote wrapper repo
  backup.rb           - orchestration: bundle+encrypt+chunk+push, and the reverse
  remote_helper.rb    - the 'man gitremote-helpers' protocol implementation
bin/
  git-remote-gpg-encrypt   - the remote-helper entrypoint (git invokes this directly)
  git-gpg-encrypt-setup    - one-time readiness check (gpg installed + passphrase set)
  git-gpg-encrypt-verify   - verify the current backup still decrypts
  git-gpg-encrypt-restore  - disaster-recovery / fresh-machine bootstrap
spec/                 - RSpec suite, including an end-to-end push/fetch test
```

## Git State Management -- Mandatory

**Do NOT modify git state (staging, commits, branches, remotes) without explicit
permission.** After making edits: show `git status`/`git diff`, then stop and let the
user review and stage/commit manually. Exception: when the user explicitly says
"commit", "stage these files", or equivalent clear intent.

## Testing

```bash
bundle install         # first time / after Gemfile changes
bundle exec rspec      # full suite
bundle exec rubocop    # lint
```

Both `gpg` and `git` must be on `PATH` for the spec suite to pass (it exercises real
`gpg`/`git` subprocesses against temp directories -- no mocking of the actual
cryptography or git plumbing).

## When to Ask Questions

Ask only if this repo's own files and `README.md` cannot answer the question. Do not ask
about anything already covered in `.ai/domains/`.
