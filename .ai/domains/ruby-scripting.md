---
applyTo: "**/*.rb"
---

# Ruby Script Instructions

> Adapted from the [dotfiles repository](https://github.com/vraravam/dotfiles)'s `.ai/domains/ruby-scripting.md`
> for this standalone project. Sections that depended on dotfiles-only infrastructure
> (a `Logging` module with colored/structured output, an `EnvVars` module, a `GitProcessor`
> class, a `CliParser` gem wrapper, and script-depth-tracking for nested log indentation)
> have been replaced with this repo's own, deliberately minimal equivalents: plain
> `warn`/`puts`, the `Config` module (`lib/git_remote_gpg_encrypt/config.rb`), and the
> `ShellGit` class (`lib/git_remote_gpg_encrypt/shell_git.rb`). Everything else -- the
> universal Ruby engineering rules -- is preserved.

Apply these rules when writing or editing any Ruby file in this repository (`lib/`,
`bin/`, `spec/`).

## Scope

**This file applies to**: All Ruby code in this repository:
- `lib/git_remote_gpg_encrypt.rb` and `lib/git_remote_gpg_encrypt/*.rb`
- `bin/*` executables (all four are Ruby, despite having no `.rb` extension --
  `git-remote-<transport>` naming is mandated by git itself, and the other three
  follow the `git-<name>` PATH-discovery convention so they can be invoked as
  `git gpg-encrypt-setup`/`-verify`/`-restore`)
- `spec/*.rb`

**Related files**:
- [`comment-philosophy.md`](./comment-philosophy.md) - Comment style and rationale
- [`character-encoding.md`](./character-encoding.md) - ASCII-only requirements
- [`whitespace-rules.md`](./whitespace-rules.md) - Whitespace verification
- [`edit-checklist.md`](./edit-checklist.md) - Post-edit verification workflow

## Quick Reference

| Task | Pattern | Section Link |
|------|---------|---------------|
| Script template | Module + thin `bin/` wrapper | [Module + `bin/` Wrapper Pattern](#module--bin-wrapper-pattern) |
| Method parameters | Named for 2+ params | [Method Parameters](#method-parameters----named-vs-positional) |
| Diagnostics | `warn` (stderr), never `puts` for errors | [Diagnostics](#diagnostics----no-logging-framework) |
| Env-var config | `Config.foo` (`lib/git_remote_gpg_encrypt/config.rb`) | [Configuration](#configuration----the-config-module) |
| Git operations | `ShellGit.new(dir)` | [ShellGit Usage](#shellgit-usage-patterns) |
| Nil check | `Core.nil_or_empty?(value)` | [`nil_or_empty?` Helper](#nil_or_empty-helper) |
| Mutating methods | Never use `strip!`/`gsub!`/etc | [Mutating Methods](#mutating-methods----avoid--variants) |
| Memoization | `@_var ||= expensive_operation` | [Memoization](#memoization) |

## File Naming Convention

- **`bin/` executables**: kebab-case where the name is user-facing (`git-gpg-encrypt-setup`,
  `git-gpg-encrypt-verify`, `git-gpg-encrypt-restore`), except `bin/git-remote-gpg-encrypt`,
  whose exact name is mandated by git's remote-helper dispatch (`man gitremote-helpers`
  INVOCATION: must be exactly `git-remote-<transport>`, no exceptions).
- **`lib/` modules**: snake_case, matching `require_relative` convention
  (`require_relative 'chunker'` -> `chunker.rb`).
- **`spec/` files**: `<module_name>_spec.rb`, snake_case, mirroring the module under test.

## Module + `bin/` Wrapper Pattern

Every `bin/` executable is a **thin wrapper**: it parses `ARGV`, prints usage on `-h`/
`--help` or wrong arg count, calls exactly one `lib/` module method, and converts that
method's boolean return value into an exit code. All business logic lives in `lib/`.

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/git_remote_gpg_encrypt'

def usage
  puts 'Usage: git gpg-encrypt-verify <remote-url>'
end

if ARGV.include?('-h') || ARGV.include?('--help')
  usage
  exit 0
end

if ARGV.size != 1
  usage
  exit 1
end

success = GitRemoteGpgEncrypt::Backup.verify_decryptable?(remote_url: ARGV[0])
exit(success ? 0 : 1)
```

**Rules:**
- `lib/` methods **never call `exit`** -- they return `true`/`false` (or, for
  `Backup.fetch_and_list_bundle_refs`, an array; empty means "nothing to report", not
  an exception). Only `bin/` files call `exit`.
- `lib/` methods use `module_function` (see every existing module for the pattern) so
  they are callable both as `Module.method(...)` and, if ever `include`d, as instance
  methods -- consistent with this being a set of small stateless-ish utility modules
  (the one exception is `ShellGit`, which is a class because it wraps per-directory
  state: the `@dir` a given instance operates on).
- Never call `exit` from inside a `lib/` module. If a `bin/` script needs to call
  another `lib/` method after one fails, check the boolean return and decide there --
  don't rely on an exception or an early `exit` deep inside `lib/`.

## Method Parameters -- Named vs Positional

Use named (`key:`) parameters for any method with 2+ parameters, or where a parameter's
meaning is not obvious from the method name alone. Single-parameter methods with an
obvious meaning may stay positional.

```ruby
# Good -- single parameter, meaning clear from name
def dir_for(remote_url)
def repo?(path)

# Good -- 2+ parameters, named
def encrypt(input_file, output_file, passphrase:)
def bundle_and_push(git_dir:, remote_url:, quiet: false)

# BAD -- positional parameters, order unclear at call sites
def encrypt(input_file, output_file, passphrase)
```

Optional parameters and boolean flags are always named, with a default:

```ruby
# Good
def clone_and_decrypt(remote_url:, target_dir:, dry_run: false)
```

## Diagnostics -- No Logging Framework

This tool deliberately has **no** structured/colored logging module -- that would be
unnecessary complexity for what is meant to be a small, auditable, dependency-light
tool. Use plain Ruby:

| Situation | Use |
|---|---|
| A problem the user needs to see, non-fatal (`lib/` returning `false`) | `warn 'message'` (writes to stderr) |
| Normal user-facing progress/output from a `bin/` command | `puts 'message'` (writes to stdout) |
| Output from `bin/git-remote-gpg-encrypt` specifically | **Never** `puts` outside the wire-protocol replies in `RemoteHelper` -- see that file's header comment. Everything else must go through `_with_stdout_redirected` or `warn`. |

Never write a bespoke color/ANSI output helper, a "log level" concept, or a message-prefix
convention for this project -- keep diagnostics as plain, single-line `warn`/`puts` calls.

## Configuration -- The `Config` Module

All environment-variable-driven settings live in `lib/git_remote_gpg_encrypt/config.rb`
as `module_function` methods with a default baked in via `ENV.fetch('VAR', default)`.
Never call `ENV.fetch`/`ENV['VAR']` for a project-defined setting anywhere else in the
codebase -- add a `Config` method instead, even for a single call site, so every tunable
is discoverable in one file.

```ruby
# BAD -- scattered ENV.fetch outside Config
chunk_size = Integer(ENV.fetch('GIT_GPG_ENCRYPT_CHUNK_SIZE_BYTES', '47185920'))

# Good -- centralized
chunk_size = Config.chunk_size_bytes
```

The one deliberate exception is `PassphraseStore.fetch`, which reads
`GIT_GPG_ENCRYPT_PASSPHRASE` directly -- that variable is not a tunable setting, it's
the actual secret input, and keeping its lookup colocated with the Keychain fallback
logic (rather than routing it through `Config`) makes the one security-sensitive read
path easier to audit in a single place.

## `ShellGit` Usage Patterns

`ShellGit` (`lib/git_remote_gpg_encrypt/shell_git.rb`) wraps plain git plumbing/porcelain
commands via `git -C <dir> <subcommand>` -- **never** a user's own git aliases, and
**never** third-party tools such as git-extras. This project must work identically on
any machine with a stock git install, regardless of the caller's own `~/.gitconfig`.

```ruby
# Good -- instantiate once per directory, call multiple methods on it
git = ShellGit.new(dir)
git.add_all
git.commit('message') unless git.nothing_staged?

# BAD -- never shell out to git directly from Backup/WrapperRepo; always go through
# ShellGit so there is one place that owns "how do we invoke git"
system('git', '-C', dir.to_s, 'add', '--all')
```

When adding a new git operation, add a method to `ShellGit` rather than an inline
`Open3.capture3('git', ...)` call elsewhere -- keeps every git invocation in one
auditable file.

## Quoting

Prefer **single quotes** for strings with no interpolation. Use **double quotes** only
when the string contains `#{}` interpolation or an escape sequence (`\n`, `\t`).

```ruby
# Good
warn 'Failed to create git bundle'
warn "Failed to create git bundle from '#{git_dir}'"

# BAD -- double quotes with no interpolation
warn "Failed to create git bundle"
```

## Exit Points -- Single Exit at End of Script

`bin/` scripts that could conceivably process multiple items must never call `exit` mid-
loop (none currently do -- each `bin/` script performs exactly one operation). If a future
`bin/` command processes multiple remotes/items, track failure state and `exit` once at
the end, so every item is still processed and a full summary can be shown. Two exceptions
remain fine at the top of a script: printing `usage` and exiting on `-h`/`--help` or a
missing/invalid argument (a precondition check, not a mid-processing abort).

## Internal Helpers -- Private Methods

Every helper method not part of a module's public API must be prefixed with `_` and
listed in a `private_class_method` (or `private`, for `ShellGit`, a class) declaration
immediately after the last helper's definition.

```ruby
module WrapperRepo
  module_function

  def ensure!(remote_url, pull_latest: false)
    # ...
    _repair_remote_tracking(git) if pull_latest
  end

  def _repair_remote_tracking(git)
    # ...
  end
  private_class_method :_repair_remote_tracking
end
```

## Comment Philosophy

See [`comment-philosophy.md`](./comment-philosophy.md). Comments explain **why**, not
**what changed** -- no changelog-style or temporal language ("now does X", "updated to
Y"). Every non-obvious design decision in this codebase (the 45MB chunk size, the
`--pinentry-mode loopback` flag, the `_with_stdout_redirected` fd trick, why `age` was
rejected as a backend) has a comment explaining the reasoning -- preserve that when
editing nearby code, and add the same treatment to new non-obvious code.

## Character Encoding

See [`character-encoding.md`](./character-encoding.md). ASCII-only in all code and
comments (`--` not em/en dash, straight quotes not curly quotes). No exceptions in this
repository -- unlike the dotfiles repo, there is no user-facing colored-logging output
where Unicode typography would ever be appropriate here.

## Formatting After Every Edit

See [`edit-checklist.md`](./edit-checklist.md) for the full workflow. Quick summary:

1. Syntax check: `/usr/bin/ruby -c <file>` (must use system Ruby -- see Version
   Compatibility below)
2. Format: `bundle exec rubocop -a <file>` (auto-correct safe offenses), then review
   `bundle exec rubocop <file>` for anything left
3. No consecutive blank lines (2+ blank lines in a row) -- collapse with:
   `awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' <file> > <file>.tmp && mv <file>.tmp <file>`
4. Verify whitespace rules ([`whitespace-rules.md`](./whitespace-rules.md))
5. `chmod +x` if the file is in `bin/`

## Version Compatibility

All Ruby code in this repository must be compatible with **Ruby 2.6** -- the system
Ruby shipped on macOS, which is what most users will actually have on `PATH` when this
tool is installed via Homebrew or `install.sh` (see `.mise.toml` and `Gemfile`'s `ruby
'2.6.10'` pin, which makes Bundler itself refuse to resolve any gem requiring newer).

Do NOT use:
- Endless range `(1..)` -- Ruby 2.7+; use `(1..Float::INFINITY)` or avoid
- Pattern matching (`case x in`) -- Ruby 3.0+
- Numbered block parameters (`_1`, `_2`) -- Ruby 2.7+
- Rightward assignment (`=> variable`) -- Ruby 3.0+
- Hash shorthand syntax (`{x:, y:}`) -- Ruby 3.1+

### Verification

```bash
/usr/bin/ruby -c path/to/file.rb
```

Must succeed with no syntax errors before formatting/committing.

## Requires

Only `require` what a file directly uses -- do not transitively pre-load. Sort `require`
statements alphabetically within each group; stdlib `require` first, then
`require_relative`, each group sorted independently, with a blank line between groups
and before the first line of actual code:

```ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'
require 'tmpdir'

require_relative 'chunker'
require_relative 'config'

module GitRemoteGpgEncrypt
  # ...
```

### Remove Unused Requires

After refactoring, always remove `require`/`require_relative` statements no longer used
-- a require is unused when the module/class is never referenced and no method/constant
from it is called anywhere in the file.

### Deleting Methods -- Mandatory Codebase Scan

Before deleting any method as "unused", grep the whole repo (`lib/`, `bin/`, `spec/`)
for its name, and check git history (`git log --all -S"def method_name" --oneline`) to
verify it isn't referenced from a WIP branch. Only delete once all checks pass.

## Environment Variables

Always use `ENV.fetch` (never bare `ENV['VAR']`) so a typo'd variable name raises instead
of silently returning `nil`:

```ruby
# BAD
value = ENV['GIT_GPG_ENCRYPT_PASSPHRASE']

# Good
value = ENV.fetch('GIT_GPG_ENCRYPT_PASSPHRASE', nil)
```

Every project-defined env var must be centralized in `Config` (see
[Configuration](#configuration----the-config-module) above) -- the only exception is
`PassphraseStore`'s direct read of `GIT_GPG_ENCRYPT_PASSPHRASE`, for the reason
explained there.

## Conditionals -- Trailing Style for Single Statements

Use trailing `if`/`unless` for a single-statement body; block style for multiple
statements or complex conditions.

```ruby
# Good -- single statement
return false if Core.nil_or_empty?(remote_url)
git.reset_hard if git.dirty?

# Good -- multiple statements, block style
if git.dirty?
  warn "'#{dir}' has uncommitted changes -- resetting to the last committed state"
  git.reset_hard
end
```

**Performance caveat:** trailing style evaluates the entire statement before checking
the condition. For an expensive operation, use block style instead:

```ruby
# BAD -- string interpolation happens even when status.success? is true
warn("Failed: #{expensive_diagnostic}") unless status.success?

# Good -- only computed when actually needed
unless status.success?
  warn("Failed: #{expensive_diagnostic}")
end
```

## Idiomatic Patterns

```ruby
items.map { |x| ... }       # not .collect
items.select { |x| ... }    # not .filter
items.any? { |x| ... }
items.reduce({}) { |acc, x| ... }  # not .inject

Array(value).each { ... }   # guards against nil

return if Core.nil_or_empty?(value)  # never replace with .empty? alone (nil-unsafe)

'text'.strip                 # never .strip! -- see Mutating Methods
```

## Mutating Methods -- Avoid `!` Variants

**Never** use mutating methods (`strip!`, `chomp!`, `gsub!`, `sub!`, `map!`, `select!`,
etc.) anywhere in this codebase. They return `nil` when no modification occurs, which
silently breaks any `value = value.strip!`-style reassignment the moment the string/array
already happened to be in its target state.

```ruby
# BAD -- gsub! returns nil if remote_branch had no leading 'refs/remotes/origin/' to strip
remote_branch = remote_head.gsub!(%r{\Arefs/remotes/origin/}, '')

# Good -- sub always returns a string
remote_branch = remote_head.sub(%r{\Arefs/remotes/origin/}, '')
```

This codebase has zero legitimate uses of mutating methods -- keep it that way. Always
use the non-mutating form (`strip`, `sub`, `gsub`, `map`, `select`, `delete`, `compact`,
`uniq`) even when the mutating form looks like it would save an allocation; the risk of
a silent `nil` is not worth it for the sizes of data this tool ever handles.

## Shell Command Execution -- `system()` and Escaping

Every git/gpg invocation in this codebase uses **direct execution** (command + args as
separate `system`/`Open3.capture3` arguments) -- never a single interpolated shell
string. Direct execution never invokes `/bin/sh`, so arguments containing spaces or
shell metacharacters (a remote URL, a passphrase, a file path under `Dir.mktmpdir`) are
passed through exactly as given, with **no escaping needed and no injection risk**:

```ruby
# Good -- safe regardless of what characters remote_url/git_dir contain
system('git', '--git-dir', git_dir.to_s, 'bundle', 'create', '--quiet', bundle_file.to_s, '--all')
Open3.capture3('git', '-C', dir.to_s, 'diff', '--quiet')

# BAD -- never do this; a URL or path containing a space or '$(...)' would be
# interpreted by a shell instead of passed through literally
system("git --git-dir #{git_dir} bundle create --quiet #{bundle_file} --all")
```

This project has **no** legitimate use case for shell-string execution (pipes,
redirection, shell functions) -- if you ever find yourself reaching for
`system("... #{var} ...")`, stop and use the array form instead.

The one place a real secret crosses a process boundary is `Encryptor`'s
`stdin_data: passphrase` to `Open3.capture3` -- this pipes the passphrase over the
child's stdin file descriptor, **never** as a command-line argument (which would be
visible to any other process on the machine via `ps` for the call's duration). Preserve
this pattern for any future secret-bearing subprocess call.

## Module / Class Organization

Order within a module/class:

1. Constants (`CAPABILITIES`, `PAD_WIDTH`, etc.)
2. Public API methods (`module_function`-declared, or public instance methods for
   `ShellGit`)
3. `private_class_method`/`private` declaration followed by internal `_`-prefixed
   helpers

```ruby
module RemoteHelper
  module_function

  CAPABILITIES = %w[fetch push option].freeze

  def run(address:)
    # ...
  end

  def _reply_capabilities
    # ...
  end
  private_class_method :_reply_capabilities
end
```

## `Core.nil_or_empty?` Helper

Always use `Core.nil_or_empty?` instead of calling `.empty?`/`.nil?` directly -- it
strips strings before checking, so a whitespace-only string counts as empty, and it
never raises on `nil`:

```ruby
Core.nil_or_empty?(nil)        # => true
Core.nil_or_empty?('')         # => true
Core.nil_or_empty?('   ')      # => true
Core.nil_or_empty?([])         # => true
Core.nil_or_empty?('text')     # => false
```

## Memoization

Memoize an expensive or repeated operation with `||=` on an instance variable when the
same method is called 3+ times per process with an unchanging result. Do NOT memoize:
single-use checks, or state that can genuinely change during the process's lifetime
(e.g. `ShellGit#dirty?`/`#current_branch` must always re-check the filesystem, since the
whole point of calling them is to observe state that this same process may have just
changed).

```ruby
# Good -- PassphraseStore.fetch is called many times per push/pull; the Keychain
# entry cannot change mid-process, so memoizing avoids repeated 'security' subprocess
# calls. (Not actually memoized in this codebase today since every call site already
# only calls it once per operation -- but this is the right pattern if that changes.)
def fetch
  return @_passphrase if defined?(@_passphrase)
  @_passphrase = _read_passphrase
end
```

## Variable Scoping and Extraction

Declare variables in the innermost scope where they're used (inside a block/branch, not
hoisted above it if only one branch needs it). Extract a local variable when a value or
expression is used 2+ times in the same method; inline it when used only once and the
expression is simple.

```ruby
# Good -- extracted because used 3 times
wrapper_dir = WrapperRepo.dir_for(remote_url)
Chunker.join(wrapper_dir, encrypted_file, basename: Config.blob_filename)
# ... later ...
Chunker.split(encrypted_file, wrapper_dir, basename: Config.blob_filename, chunk_size_bytes: Config.chunk_size_bytes)
```

## Destructive Operations -- Capture Metadata Before Destruction

Before any operation that discards state (`ShellGit#reset_hard`, deleting a temp file,
overwriting a wrapper repo's chunks), capture everything you'll need to recover or
report on **before** the destructive call, not after:

```ruby
# Good -- WrapperRepo.ensure! captures 'dir' for its warning message before git.reset_hard
# would make any subsequent read of that state meaningless
if git.dirty?
  warn "'#{dir}' has uncommitted changes -- resetting to the last committed state"
  git.reset_hard
end
```

## String Operations -- Performance-Aware Patterns

Prefer the most specific String method for the operation -- each is measurably faster
than a more general one for the same job, and this codebase is not so performance-
insensitive that the choice never matters (chunk/refspec parsing runs on every
push/pull):

| Instead of | Use | Why |
|---|---|---|
| `gsub('/', '-')` (single char) | `tr('/', '-')` | ~3x faster |
| `gsub('/', '')` (removal) | `delete('/')` | ~4x faster than gsub |
| `gsub(/\.git$/, '')` (single match) | `sub(/\.git$/, '')` | ~2x faster (stops at first match) |
| `sub(/^prefix/, '')` (static prefix) | `delete_prefix('prefix')` | ~3x faster, Ruby 2.5+ |
| `sub(/suffix$/, '')` (static suffix) | `delete_suffix('suffix')` | ~3x faster, Ruby 2.5+ |

## Loop-Invariant Hoisting

If a computed value doesn't change across a loop's iterations, compute it once before
the loop:

```ruby
# BAD -- recompiles the same Regexp on every element
repos.select { |r| r.match?(/#{filter}/i) }

# Good -- compiled once, reused for every element
filter_re = Regexp.new(filter, Regexp::IGNORECASE)
repos.select { |r| r.match?(filter_re) }
```

## Set vs Array -- Membership Checks

`Array#include?` is O(n); `Set#include?` is O(1) average. Convert to `Set` only when a
collection is checked with `.include?` more than once AND has enough elements (or is
checked often enough) for the difference to matter -- a one-off check on a handful of
elements is not worth the conversion or the `require 'set'`.

## Enumerable Chains -- Avoid Intermediate Allocation

Prefer the direct combinator over `.select{}.any?`/`.sort.first`-style chains that build
and discard an intermediate collection:

| Wasteful | Direct |
|---|---|
| `arr.select { }.any?` | `arr.any? { }` |
| `arr.select { }.count` | `arr.count { }` |
| `arr.sort_by { }.first` | `arr.min_by { }` |
| `arr.sort_by { }.last` | `arr.max_by { }` |

## Early-Exit Before Expensive Computation

When a method does non-trivial work (regex matching, subprocess calls) that a caller
immediately discards based on a cheap, already-known condition, move that cheap check to
the top of the method instead of the bottom.

## Common Mistakes (Code Review Findings)

1. **Calling a mutating method (`gsub!`/`strip!`/etc.)** -- always use the non-mutating
   form; see [Mutating Methods](#mutating-methods----avoid--variants).
2. **Interpolating a shell command string instead of using array-form `system`/`Open3`**
   -- see [Shell Command Execution](#shell-command-execution----system-and-escaping).
3. **Calling `exit` inside a `lib/` module** -- only `bin/` files call `exit`; `lib/`
   methods return booleans.
4. **`ENV['VAR']` instead of `ENV.fetch('VAR', default)`** -- typos silently return
   `nil` with the former.
5. **Adding a new environment variable without a `Config` method** -- see
   [Configuration](#configuration----the-config-module).
6. **Shelling out to `git` directly instead of adding a `ShellGit` method** -- see
   [`ShellGit` Usage Patterns](#shellgit-usage-patterns).
7. **Forgetting `.freeze` on a module-level constant array/hash.**
8. **Not quoting a passphrase's stdin path correctly** -- always pass secrets via
   `stdin_data:`, never as a CLI argument; see [Shell Command
   Execution](#shell-command-execution----system-and-escaping).
