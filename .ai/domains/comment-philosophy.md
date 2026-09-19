---
applyTo: "**/*.rb,**/*.sh"
---

# Comment Philosophy

> Adapted from the dotfiles repository's `.ai/domains/comment-philosophy.md` for this
> standalone project (Ruby-only; the shell-script examples were dropped since this
> repo's only shell script is `install.sh`).

Comments must serve as **timeless reference documentation**, not a changelog or commit
message.

## Scope

**This file applies to**: All code comments in this repository -- `lib/*.rb`, `bin/*`,
`spec/*.rb`, and `install.sh`.

**Related files**:
- [`character-encoding.md`](./character-encoding.md) - ASCII-only requirements for comments
- [`edit-checklist.md`](./edit-checklist.md) - Post-edit verification workflow

**Does NOT apply to**: Commit messages (use git conventions) or markdown documentation.

## Quick Reference

| Type | Good Example | Bad Example |
|------|-------------|-------------|
| **WHY** explanation | `# 45MB stays under GitHub's 50MB warning threshold` | `# Now uses 45MB` |
| **WHAT** edge case | `# Returns [] if nothing has been pushed yet, not an error` | `# Handles empty case` |
| **HOW** to use | `# eg: git gpg-encrypt-restore <url> ~/restored` | `# Added restore command` |
| **WHEN** condition | `# Only meaningful when quiet: false` | `# Currently always runs` |
| Avoid | Present-tense rationale | Past-tense changelog |

## Comment Format

```ruby
# frozen_string_literal: true

module GitRemoteGpgEncrypt
  # One or two sentences describing this module's single responsibility.
  module Chunker
    module_function

    # Splits input_file into fixed-size chunks -- see the file header for why this
    # exists (GitHub's 100MB hard file-size limit).
    #
    # @param input_file [String, Pathname] file to split
    # @param output_dir [String, Pathname] directory to write chunk files into
    # @param basename [String] chunk filename prefix
    # @param chunk_size_bytes [Integer] max size per chunk
    # @return [void]
    def split(input_file, output_dir, basename:, chunk_size_bytes:)
      # Implementation-level comment where the "why" isn't obvious from the code alone.
    end
  end
end
```

**Conventions**:
- Plain `#` with a single space before the text -- no boxed/banner headers.
- YARD `@param`/`@return`/`@raise`/`@yield`/`@yieldparam` tags document method
  signatures (established convention throughout this codebase). These
  complement, not replace, the WHY-explanation prose above them: a tag states
  the type/shape mechanically, prose explains anything non-obvious about it.
  Skip a tag only when it would add zero information beyond the parameter/
  method name itself.
- A module or class gets a short doc comment above its definition explaining its single
  responsibility (see every existing file in `lib/` for the pattern).
- A non-obvious method gets a comment explaining **why** it exists or why it's
  implemented the way it is -- not a restatement of its name.

## What Good Comments Explain

**Good comments explain:**
- **Why** a non-obvious implementation choice was made (e.g., why chunks are 45MB, not
  50MB or 100MB; why the passphrase is piped via stdin instead of a CLI flag; why `age`
  was considered and rejected).
- **What** edge case is being handled (e.g., "an empty ref list means nothing pushed
  yet, not a failure").
- **How** to use something correctly (usage examples in `bin/` usage text).
- **When** a condition matters (e.g., "only meaningful when quiet: false").

**Bad comments describe:**
- **Past changes** ("now returns nil instead of raising", "switched from X to Y").
- **Commit-specific context** ("fixed in this PR", "removed the old chunking logic").
- **Temporal language** ("currently does X", "as of this version").
- **The obviously-restated code** (`index += 1  # increment index`).

## Examples

```ruby
# BAD -- describes a change, not current behavior
# Switched from gpg-agent caching to --passphrase-fd for non-interactive use.
'--passphrase-fd', '0',

# GOOD -- explains why the current approach is used
# Piped over stdin, never a CLI argument -- a CLI arg would be visible to other
# processes on the machine via 'ps' for the duration of the call.
'--passphrase-fd', '0',

# BAD -- changelog-style
# Now checks nothing_staged? before committing.
return true if git.nothing_staged?

# GOOD -- explains the actual reason
# A no-op commit would fail; treat "nothing changed since last push" as success.
return true if git.nothing_staged?
```

## Rationale

1. **Comments are documentation, not commit history** -- use `git log` for history.
2. **Future readers need the current state**, not how it evolved.
3. **Temporal language goes stale** the moment the next change lands.
4. **"Why" explanations prevent regressions** -- a future refactor won't reintroduce a
   bug the original comment already warned about.

## When Updating Code

1. Remove or reword any comment describing past (not current) behavior.
2. Add/update comments to explain current behavior and its rationale.
3. Put historical context in the commit message, not inline.
