---
applyTo: "Gemfile,Gemfile.lock"
---

# Dependency Update Security Review

These instructions apply Copilot code review to pull requests that change
`Gemfile` or `Gemfile.lock` -- in practice, almost always a Dependabot
version-bump PR (see `.github/dependabot.yml`). They cover what's actually
relevant for a dependency bump in this repo; a lockfile diff has no command
injection, sudo usage, or TOCTOU races to review, so this checklist is
narrower than a general script security review.

When reviewing a `Gemfile`/`Gemfile.lock` change:

1. **Known vulnerabilities**: `bundler-audit` (run automatically by
   `.github/workflows/dependabot-audit.yml`) already checks the Ruby Advisory
   Database -- do not re-derive this from scratch, but do flag it as a
   CRITICAL finding if that workflow's `bundler-audit` step failed.

2. **Ruby 2.6 compatibility**: This repo pins `ruby '2.6.10'` in `Gemfile` as
   a hard ceiling (see `Gemfile`'s comment for the full rationale -- this tool
   must run on the vanilla macOS system Ruby, see `.ai/domains/ruby-scripting.md`
   Section: Version Compatibility). Flag any gem version bump that would
   require Ruby >= 2.7 as a CRITICAL finding, even if Bundler's resolver
   accepted it (the pin should prevent this, but a manually-edited
   `Gemfile.lock` could bypass it).

3. **Unexpected transitive dependencies**: Compare the diff's added/removed
   entries in `Gemfile.lock` against the direct gems declared in `Gemfile`
   (`rspec`, `simplecov`, `rubocop`, `rubocop-ast`, `bundler-audit`). A large,
   unrelated set of new transitive dependencies pulled in by a small version
   bump is worth flagging as MEDIUM risk -- it may indicate the new release
   significantly changed its own dependency tree.

4. **Gem source/provenance**: Confirm every gem still resolves from
   `https://rubygems.org` (the only `source` declared in `Gemfile`). A diff
   that introduces a git/path source, or changes the declared `source`, is a
   CRITICAL finding -- this is the most common supply-chain attack vector for
   a Bundler project.

5. **Version pin changes**: This repo pins exact versions for `rspec`,
   `simplecov`, `rubocop`, `rubocop-ast`, and `bundler-audit` in `Gemfile`
   (not `~>` or open ranges) specifically to avoid `prism`-dependent releases
   that need Ruby >= 2.7 (see `Gemfile` comments). Flag any diff that loosens
   a pin to a range as MEDIUM risk -- even if the immediate bump is fine, an
   open range defeats the reason the pin exists.

This repo has zero runtime gem dependencies (see `Gemfile`'s own comment) --
every gem declared is `group :development, :test` tooling only, so a
compromised dependency here could only affect local development/CI, never
anything shipped to a user running this tool.
