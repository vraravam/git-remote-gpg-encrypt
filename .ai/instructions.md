# git-remote-gpg-encrypt -- AI Assistant Instructions

This is the main entry point for any AI coding assistant working on this repository.
Domain-specific rules are in [`domains/`](./domains/).

## Loading Strategy

1. **Always loaded**: this file, [`whitespace-rules.md`](./domains/whitespace-rules.md) and
   [`edit-checklist.md`](./domains/edit-checklist.md).
2. **Load on demand**: the domain file(s) matching the task (table below).
3. **Do not preload everything.** Reading every file wastes context and buries the rules
   that matter.

These files are plain markdown with YAML frontmatter (`applyTo`, `name`, `description`) and
assume only generic capabilities (read, edit, search, run a shell command), so any assistant
can use them.

## Instruction Files

| Domain | File | Read when |
|--------|------|-----------|
| Ruby scripting | [`domains/ruby-scripting.md`](./domains/ruby-scripting.md) | Any `.rb` file and `bin/*` executables |
| Comment philosophy | [`domains/comment-philosophy.md`](./domains/comment-philosophy.md) | Writing or changing comments |
| Character encoding | [`domains/character-encoding.md`](./domains/character-encoding.md) | Anything that may contain non-ASCII characters |
| Whitespace rules | [`domains/whitespace-rules.md`](./domains/whitespace-rules.md) | After every edit (always loaded) |
| Edit checklist | [`domains/edit-checklist.md`](./domains/edit-checklist.md) | After every edit (always loaded) |
| Changelog maintenance | [`domains/changelog-maintenance.md`](./domains/changelog-maintenance.md) | `CHANGELOG.md` entries, commits, release tagging |

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

## Periodic Review -- Keep the Context Budget Healthy

Instruction files only grow. Review the `.ai/` layout whenever a release is cut (or roughly
quarterly), and whenever one rule addition pushes a file past a threshold below.

**Measure** (bytes; about 4 bytes per token):

```bash
wc -c AGENTS.md .ai/instructions.md .ai/domains/whitespace-rules.md .ai/domains/edit-checklist.md;
wc -c .ai/domains/*.md | sort -rn;
```

| Item | Target | Action when exceeded |
|------|--------|----------------------|
| Always-loaded total (`AGENTS.md`, `instructions.md`, `whitespace-rules.md`, `edit-checklist.md`) | 20 KB or less | Move situational rules into an on-demand domain file; link instead of restating |
| Any single domain file | 30 KB or less | Split into a core file plus topic files; keep a "Topic Files" table in the core |
| `AGENTS.md` | 6 KB or less | Keep only hard rules, the routing table and one-line pointers |

**Checklist for each review:**

1. Re-measure and compare against the thresholds.
2. Look for rules duplicated across files; keep one canonical home and link to it.
3. Promote rules every edit needs into an always-loaded file, and demote rarely-needed ones to an on-demand file.
4. After any move, check that every markdown link resolves and every `§ Heading` reference names the file that holds that heading.
5. Keep the routing table in `AGENTS.md`, the table above, and the `.opencode/skills/` symlinks (one per on-demand domain file; directory name equal to the frontmatter `name`) in sync with `domains/`.
6. Confirm each domain file has `applyTo`, `name` and a "Use when..." `description`.
7. Remove model- or harness-specific guidance.
8. This repo's rules are an adapted subset of the dotfiles repository's. When that repo restructures or changes a rule that also applies here, check whether an adapted version belongs here too.
