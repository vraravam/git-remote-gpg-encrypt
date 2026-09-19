---
applyTo: "**/*.rb,**/*.sh,**/*.md"
---

# Character Encoding and Punctuation

> Adapted from the dotfiles repository's `.ai/domains/character-encoding.md` for this
> standalone project.

All code, comments, and documentation in this repository must use **ASCII-only
characters**. Never use Unicode punctuation (em dashes, en dashes, curly quotes, or
other typographic symbols).

## Scope

**This file applies to**: `lib/*.rb`, `bin/*`, `spec/*.rb`, `install.sh`, and markdown
documentation (`README.md`, `CHANGELOG.md`, this `.ai/` directory).

**Related files**:
- [`edit-checklist.md`](./edit-checklist.md) - Verification workflow after edits
- [`whitespace-rules.md`](./whitespace-rules.md) - Related text formatting rules

**Does NOT apply to**: Nothing in this repository is exempt -- unlike the dotfiles
repository (which has a colored-logging framework with user-facing typography), this
tool has no output path where Unicode punctuation would ever be appropriate.

## Rule: Use ASCII Dashes Only

```ruby
# Good -- ASCII double dash for parenthetical comments
# This avoids a stray pinentry popup on some configurations -- harmless elsewhere.

# BAD -- em dash (Unicode U+2014), shown here only to illustrate what to avoid
# This avoids a stray pinentry popup on some configurations \u2014 harmless elsewhere.
```

## Rule: Use ASCII Quotes Only

```ruby
# Good -- ASCII straight quotes
warn "Failed to decrypt '#{encrypted_file}'"

# BAD -- curly quotes (Unicode), shown here only to illustrate what to avoid
warn "Failed to decrypt \u2018file.gpg\u2019"
```

## Why ASCII-Only?

1. **Syntax highlighters**: Unicode punctuation in code/comments can break some editors'
   highlighting.
2. **Terminal compatibility**: not all terminals (especially minimal/SSH environments,
   which this tool's users may well be running `git push`/`git pull` from) render
   Unicode punctuation correctly.
3. **Copy-paste safety**: Unicode characters can be silently mangled when copied between
   systems -- especially relevant for a security tool where a mangled passphrase or
   command would be a real problem.
4. **Searchability**: ASCII dashes/quotes are trivially greppable; Unicode variants
   require special handling.
5. **Git diffs**: some diff viewers render Unicode punctuation as escape sequences.

## Verification

```bash
# Find any non-ASCII characters in a file
grep -P -n '[^\x00-\x7F]' path/to/file.rb
```

**Fix**: replace with ASCII equivalents -- em dash `--`, en dash `-`, curly quotes `"`/`'`.
