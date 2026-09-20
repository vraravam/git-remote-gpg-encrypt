---
applyTo: "CHANGELOG.md"
---

# Changelog Maintenance

> Adapted from the dotfiles repository's `.ai/instructions.md` Section: Changelog
> Generation Rules, for this standalone project. Kept: the mandatory
> one-entry-per-commit rule, entry structure/grouping conventions, and the
> amend/squash rewrite rules (all fully generic). Dropped: zsh `.zwc` cache reload,
> `.shellrc`/`.aliases` reload reminders, and `install-dotfiles.rb`/fresh-install
> instructions -- none of that infrastructure exists here. Replaced with this repo's
> own equivalent "what to tell the adopter" triggers (`bin/*` usage changes, env var
> changes, Homebrew tap bump), plus a GitHub Release mirroring step this repo's
> personal-tap distribution model needs that dotfiles (not itself brew-distributed)
> does not.

## Scope

**This file applies to**: `CHANGELOG.md` maintenance -- when and how to add, structure,
and (when amending/squashing) rewrite its entries.

**Related files**:
- [`edit-checklist.md`](./edit-checklist.md) - Runs before a commit is made; this file
  governs what goes into that commit's `CHANGELOG.md` section.

**Does NOT apply to**: `README.md`, `docs/DESIGN.md`, or any other documentation file.

## Mandatory: Every Commit Includes a CHANGELOG.md Section

**Every commit to this repository MUST include a new `CHANGELOG.md` section**, staged
and committed atomically alongside the change it documents.

### Workflow

1. Make all code/documentation changes.
2. Decide the next version number (semantic versioning: MAJOR for a breaking change to
   the `gpg-encrypt::` wire format, chunk layout, or any `bin/*` command's arguments;
   MINOR for a backward-compatible feature; PATCH for a fix). If a `git next-version`
   alias is available (see dotfiles' `git config` -- it is a global, per-user alias, not
   specific to any one repo), use it as a starting point, but override its patch-only
   assumption whenever the change is actually a MINOR/MAJOR bump.
3. Update `VERSION` in `lib/git_remote_gpg_encrypt/version.rb` to match.
4. Add a new section to `CHANGELOG.md` (see Section: Entry Structure below) documenting
   ALL changes in the commit, not just the "main" one.
5. Stage all changes, including `CHANGELOG.md` and `version.rb`.
6. Create ONE atomic commit containing both the changes and the `CHANGELOG.md` entry.

### Rules

- The entry must document ALL changes in the commit, not just the "main" change.
- Include changes to `.ai/` instructions when they're part of the same logical change
  (e.g., adding a feature + documenting the pattern in instructions).
- Never create a separate commit for a `CHANGELOG.md` update -- it belongs in the same
  commit as the change it documents.
- **Never include line number references** -- they go stale as files are edited and add
  no value to an adopter reading the entry later.
- When generating an entry, first examine the actual staged diff -- do not describe
  intended changes that never made it into the diff, or vice versa.
- If `bin/*`'s usage text or argument handling changed, note that existing shell aliases
  or scripts invoking it may need updating.
- If an environment variable was added, renamed, or removed (see `Config`), note it --
  and update the Environment Variables table in `README.md` in the same commit.
- If the change affects what a fresh Homebrew/`curl` install would do differently
  (new `bin/` executable, new dependency), note that `README.md`'s Installation/
  Requirements sections need a matching update in the same commit.

## Tagging a Release: Mirror the Entry into a GitHub Release

Once `CHANGELOG.md`/`version.rb` are updated and committed, tag and push, then create a
matching GitHub Release whose notes are that `CHANGELOG.md` section's content verbatim
(not auto-generated from commit messages) -- this is what most Homebrew-tap users
actually check first (via `brew info`'s homepage link, or the repo's own Releases tab),
rather than reading `CHANGELOG.md` directly:

```bash
git tag "v$(ruby -e "require './lib/git_remote_gpg_encrypt/version'; puts GitRemoteGpgEncrypt::VERSION")"
git push --tags
gh release create "v<version>" --title "v<version>" --notes-file <(sed -n '/^### <version>/,/^---$/p' CHANGELOG.md)
```

After the release exists, update the formula in the
[`homebrew-tap`](https://github.com/vraravam/homebrew-tap) repo to point at the new
tag/sha256 -- that repo has its own commit, separate from this one.

## Amending a Commit -- Eliminate Intermediate-State Cruft

**MANDATORY: When amending (or squashing) a commit that already has an existing
`CHANGELOG.md` section and/or commit message, both must be rewritten to describe only
the final, squashed state -- never left as a chronological narrative of intermediate
edits.**

This applies whenever a commit is amended with new changes, or multiple commits are
squashed together (e.g. `git reset --soft <base>` followed by a single new commit). Do
not simply append new bullets/paragraphs describing the newest edit on top of what was
already there -- both artifacts must be re-derived from the final squashed diff.

**Workflow:**

1. After finalizing the squash/amend's staged content, get the full diff for the
   amended commit's overall range: `git diff <original-base> <final-staged-tree>` (or
   per-file: `git diff <original-base> -- <file>`).
2. Cross-check **every existing CHANGELOG bullet** (and every paragraph of the existing
   commit message) against that final diff, file by file:
   - If a bullet describes something that does not appear at all in the final diff
     (e.g. a feature added in one intermediate commit and fully reverted/replaced in a
     later one within the same squash) -- it is pure intermediate-state cruft. **Delete
     the bullet entirely.**
   - If a bullet's specific claim was true of an intermediate commit but has since been
     further changed by a later edit in the same squash -- **rewrite the bullet to
     describe only the final, accurate behavior.** Never leave a claim that contradicts
     the actual staged/committed diff.
   - If two bullets (originally written for two separate, now-squashed commits) both
     describe the same file/behavior, and the second supersedes/extends the first --
     **merge them into one bullet** describing the final state.
3. Apply the same cross-check to the **commit message** -- it must read as a single,
   coherent description of the final change, not a stitched-together history of "first
   this happened, then this fix." Remove or rewrite any paragraph that only made sense
   as a description of an intermediate, now-superseded state.
4. Verify the rewritten `CHANGELOG.md` section and commit message pass a final
   read-through: every claim should be independently verifiable against
   `git diff <original-base> <final-state>` for the specific file/behavior it describes.

**Why this matters:** once commits are squashed, the intermediate commits never existed
from the reader's perspective -- an entry that still narrates them (e.g. "removed the X
we added earlier in this same entry", or "now calls Y directly" when the final code
doesn't) is actively misleading, not just imprecise.

## Entry Structure

When creating or editing `CHANGELOG.md` sections, follow these rules:

1. **Group related changes by category** rather than listing individual files when
   multiple files share similar changes.
   - Use `` `all bin/ executables` `` or `` `lib/git_remote_gpg_encrypt/` `` as the
     lead-in for changes that apply across multiple files with the same pattern,
     rather than one bullet per file (see `CHANGELOG.md`'s existing entries for the
     established `` - `path` -- description `` bullet style).

2. **Keep essential technical details** while removing redundant specifics:
   - Include: method names, key implementation details, specific behavior changes.
   - Remove: line numbers; repetitive file-by-file descriptions when a category
     description suffices.

3. **Use concise, high-level summaries** in the adoption section:
   - Focus on user-visible actions (re-run `git gpg-encrypt-setup`, update an env var,
     `brew upgrade`).
   - Remove implementation details already covered in the bullet points above.

4. **Structure each version section consistently**:
   - Version number header: `### X.Y.Z`
   - Descriptive subheading summarizing the theme: `#### Short theme description`
   - Bullet points with specific changes (technical details, no line numbers)
   - `#### Adopting these changes` section with user action items (optional -- omit if
     no user action is required)

5. **Version section spacing and visual separation**:
   - Each version section (starting with `### X.Y.Z`) must be separated by **exactly
     one blank line, followed by a horizontal rule (`---`), followed by one blank
     line**.
   - Pattern: `[end of previous section]\n\n---\n\n### X.Y.Z`.
   - Horizontal rule before the first version section (one blank line after the file's
     introductory `# Changelog` header, then `---`, then one blank line before the
     first `### X.Y.Z`).
   - Horizontal rule after the last version section (one blank line after last content,
     then `---` as the final line of the file).

**Example of good structure:**

```markdown
# Changelog

---

### 0.2.0

#### Add retry/backoff to WrapperRepo.ensure!'s clone step

- `lib/git_remote_gpg_encrypt/wrapper_repo.rb` -- `ensure!` now retries a failed
  `git clone` up to 3 times with a short delay -- found via real-world use against a
  flaky host that occasionally drops the connection mid-clone.

#### Adopting these changes

- No action needed -- purely internal resilience improvement.

---
```
