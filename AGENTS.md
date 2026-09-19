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
post-edit workflow.
