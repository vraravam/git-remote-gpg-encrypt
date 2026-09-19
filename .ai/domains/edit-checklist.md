---
applyTo: "**/*.rb,**/*.sh"
---

# Edit Checklist

> Adapted from the dotfiles repository's `.ai/domains/edit-checklist.md` for this
> standalone project. Trimmed to Ruby (this repo's only language) plus a minimal step
> for `install.sh`, the one shell script. Dropped entirely: zsh-specific steps
> (`.zwc` byte-compilation cache, `shfmt`/`.shfmtignore`) that don't apply here.

Apply this checklist after every edit to any file in this repository.

## Quick Reference

| Step | Ruby (`lib/`, `bin/`, `spec/`) | `install.sh` |
|------|------|--------------|
| 1. Ruby 2.6 compatibility | check | N/A |
| 2. Syntax | `/usr/bin/ruby -c file` | `bash -n install.sh` |
| 3. Format/lint | `bundle exec rubocop file` | N/A |
| 4. Whitespace | checks 1-3 | checks 1-3 |
| 5. Executable | `chmod +x` (`bin/*`, `install.sh` only) | `chmod +x` |

## Step 1 -- Ruby 2.6 Compatibility (Ruby files only)

Do NOT use: endless range (`1..`), pattern matching (`case x in`), numbered block
params (`_1`), rightward assignment (`=> var`), hash shorthand (`{x:, y:}`) -- all
require Ruby 2.7+ or later. See [`ruby-scripting.md`](./ruby-scripting.md)
Section: Version Compatibility.

## Step 2 -- Syntax Verification

```bash
/usr/bin/ruby -c path/to/file.rb   # must use system Ruby, matching what real users have
bash -n install.sh                  # install.sh only
```

Both must succeed with no errors before proceeding.

## Step 3 -- Format / Lint (Ruby files only)

```bash
bundle exec rubocop -a path/to/file.rb   # auto-correct safe offenses
bundle exec rubocop path/to/file.rb      # review anything left unresolved
```

## Step 4 -- Whitespace Rules

See [`whitespace-rules.md`](./whitespace-rules.md) for the three checks and fixes. All
non-markdown files edited in this repository must pass all three.

Also check for consecutive blank lines (2+ in a row) in Ruby files:

```bash
grep -Pzo '\n\n\n' path/to/file.rb && echo "Has consecutive blank lines"
```

**Fix**: `awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' <file> > <file>.tmp && mv <file>.tmp <file>`

## Step 5 -- Executable Permission

After editing any file in `bin/`, or `install.sh`, ensure it's still executable (some
editing methods that rewrite a file from scratch can lose the executable bit):

```bash
[[ -x path/to/file ]] && echo "OK" || chmod +x path/to/file
```

## Step 6 -- Run the Test Suite

After any change to `lib/`, run the full spec suite before considering the change done:

```bash
bundle exec rspec
```

All specs must pass. See `spec/` for the existing coverage -- add a new spec (or extend
an existing one) for any new `lib/` behavior rather than relying on manual testing alone.
