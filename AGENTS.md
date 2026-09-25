# Agent Quick Reference

This repository uses a small instruction system in `.ai/`, adapted from the
[dotfiles repository](https://github.com/vraravam/dotfiles)'s own conventions.
**Load `.ai/instructions.md` first.**

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

## OpenCode-Specific Notes

`.opencode/opencode.json` force-loads only `.ai/instructions.md` plus the small,
cross-cutting domains (`whitespace-rules.md`, `edit-checklist.md`,
`character-encoding.md`, `comment-philosophy.md`) into every session. The two larger,
situational domains (`ruby-scripting.md`, `changelog-maintenance.md`) are exposed as
on-demand skills instead -- `.opencode/skills/gpg-encrypt-ruby-scripting/SKILL.md` and
`.opencode/skills/gpg-encrypt-changelog-maintenance/SKILL.md`, each a **symlink** into
the corresponding `.ai/domains/` file (not a copy), loaded only when opencode
recognizes the current task matches. `opencode.json` also denies the same
git-state-modifying commands (`git commit`, `git push`, `git rebase`, etc.) called out
above under `permission.bash`, so the rule is enforced, not just documented.

