# Agent Quick Reference

This repository uses a small instruction system in `.ai/`, adapted from the
[dotfiles repository](https://github.com/vraravam/dotfiles)'s own conventions.
Load only what the task needs -- do not read every file under `.ai/`.

## Loading Strategy

- **Always read**: this file, [`.ai/instructions.md`](.ai/instructions.md),
  [`.ai/domains/whitespace-rules.md`](.ai/domains/whitespace-rules.md) and
  [`.ai/domains/edit-checklist.md`](.ai/domains/edit-checklist.md) before editing.
- **Read on demand**:

| If the task touches... | Read (under `.ai/domains/`) |
|------------------------|-----------------------------|
| Any Ruby file (`lib/`, `bin/`, `spec/`) | `ruby-scripting.md` |
| Writing or changing comments | `comment-philosophy.md` |
| Text that may contain non-ASCII characters | `character-encoding.md` |
| A commit, release, or `CHANGELOG.md` | `changelog-maintenance.md` |

## Quick Facts

- **Ruby 2.6 compatible** (macOS system Ruby) -- see `Gemfile`'s `ruby '2.6.10'` pin and
  `.mise.toml`.
- **No logging/color framework, no `EnvVars`, no `GitProcessor`, no `CliParser`** --
  this is a deliberately minimal, dependency-light tool. See
  `.ai/domains/ruby-scripting.md` for what replaced each of those.
- **Every git operation goes through `ShellGit`** -- never a user's own git aliases or
  third-party tools like git-extras.
- **Every environment variable is centralized in `Config`** -- never a bare `ENV.fetch`
  scattered elsewhere (except `PassphraseStore`'s passphrase read; see that file).
- **Never use a mutating String/Array method** (`gsub!`, `strip!`, etc.) -- see
  `.ai/domains/ruby-scripting.md` Mutating Methods.

## Git State Management

Do NOT stage, commit, or push without explicit permission. Show `git status`/`git diff`
after edits and stop there -- let the user review and stage manually.

## Before Committing

```bash
bundle exec rspec        # full test suite must pass
bundle exec rubocop      # lint must pass
```

See `.ai/instructions.md` and `.ai/domains/edit-checklist.md` for the complete
post-edit workflow, and `.ai/domains/changelog-maintenance.md` -- every commit needs a
matching `CHANGELOG.md` section.

## Tool Entry Points

- **AGENTS.md-aware tools (OpenCode, Codex, Cursor, etc.)**: this file.
- **Claude Code**: `CLAUDE.md` (imports this file) and `.claude/skills` (a symlink to
  `.opencode/skills`).
- **OpenCode**: `.opencode/opencode.json` force-loads only `.ai/instructions.md`,
  `whitespace-rules.md` and `edit-checklist.md`. Every other domain file is an on-demand
  skill under `.opencode/skills/gpg-encrypt-<domain>/SKILL.md`, each a **symlink** into the
  matching `.ai/domains/` file (not a copy), so there is one physical file per domain.
  `opencode.json` also denies the git-state-modifying commands called out above
  (`git commit`, `git push`, `git rebase`, etc.) under `permission.bash`, so the rule is
  enforced, not just documented.

## Maintenance

When adding or moving rules, or on the periodic cadence, follow
`.ai/instructions.md` § Periodic Review.
