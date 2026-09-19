---
applyTo: "**/*"
---

# Whitespace Rules

> Adapted from the dotfiles repository's `.ai/domains/whitespace-rules.md` for this
> standalone project (content is fully generic; only the scope section was trimmed).

After every edit to any file (except `.md` files), the file **MUST pass all three
whitespace checks**.

## Scope

**This file applies to**: All text files in this repository except markdown --
`lib/*.rb`, `bin/*`, `spec/*.rb`, `install.sh`, `Gemfile`, `.rubocop.yml`, `.mise.toml`,
`.gitignore`, `.editorconfig`.

**Related files**:
- [`edit-checklist.md`](./edit-checklist.md) - Complete post-edit verification workflow
- [`character-encoding.md`](./character-encoding.md) - ASCII-only requirements

**Does NOT apply to**: Markdown files (`.md`) are exempt from Check 2 only (trailing
blank lines allowed).

## Check 1: File Ends with Newline

```bash
tail -c 1 <file> | od -An -tx1 | grep -q '0a' || echo "FAIL: Missing final newline"
```

**Fix**: `echo "" >> <file>`

## Check 2: No Trailing Blank Lines

```bash
tail -n 1 <file> | grep -q '^$' && echo "FAIL: Has trailing blank lines"
```

**Fix** (macOS/BSD sed): `sed -i '' -e :a -e '/^\s*$/d;N;ba' <file>`

## Check 3: No Trailing Whitespace on Any Line

```bash
grep -n '[[:space:]]$' <file> && echo "FAIL: Lines above have trailing whitespace"
```

**Fix** (macOS/BSD sed): `sed -i '' 's/[[:space:]]*$//' <file>`

## All-in-One Verification

```bash
if tail -c 1 <file> | od -An -tx1 | grep -q '0a' && \
   ! tail -n 1 <file> | grep -q '^$' && \
   ! grep -q '[[:space:]]$' <file>; then
  echo "OK: all whitespace checks pass"
else
  echo "FAIL: whitespace violations found"
fi
```

## When Using the Edit Tool

- Ensure `newString` ends with exactly one newline.
- No blank lines after the last content line.
- No trailing spaces/tabs on any line.

## Exceptions

- **Markdown files (`.md`)** are exempt from Check 2 only. Checks 1 and 3 still apply.
