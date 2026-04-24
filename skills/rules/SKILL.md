---
name: Custom Rules
description: Use when the user runs /ruby-upgrade-toolkit:rules or asks to add, list, validate, show, remove, disable, enable, or explain project-specific upgrade rules — gem pins, gem swaps, private-source substitutions (Rails LTS, Sidekiq Pro), verification gates (Brakeman, Reek), policy overrides. Reads and writes .ruby-upgrade-toolkit/rules.yml at the project root.
argument-hint: "[init | validate | list | show <id> | add <type> | remove <id> | disable <id> | enable <id> | explain]"
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
version: 0.1.0
---

# Custom Rules

Manage the project's custom rules file at `.ruby-upgrade-toolkit/rules.yml`.
The other commands (`audit`, `plan`, `fix`, `upgrade`, `status`) pick this
file up automatically — this skill is purely for authoring and introspection.

**Design philosophy.** The rules file is project policy, committed to the
repo. This skill is a convenience layer over it: power users can edit the
YAML by hand and everything still works. Every mutating subcommand shows a
diff and confirms before writing.

**Backward compatibility guarantee.** With no `rules.yml`, every command in
this toolkit behaves byte-identically to a version without this feature. The
file is strictly additive.

## Canonical references

Load once at the start, reuse for every subcommand:

- **Schema** — `$CLAUDE_PLUGIN_ROOT/skills/rules/references/schema.md`
  Data model for every rule type, all fields, all constraints.
- **Engine** — `$CLAUDE_PLUGIN_ROOT/skills/rules/references/rules-engine.md`
  The shared load/validate/preflight logic used by this skill AND by the
  other skills that consume rules. Same algorithms, one source of truth.
- **Starter template** — `$CLAUDE_PLUGIN_ROOT/skills/rules/references/starter-template.yml`
  Exact YAML written by `init`. Kept valid against the current schema as a
  golden-test subject.

## Subcommand Dispatch

Parse the first argument; everything after is subcommand-specific.

| Arg | Handler |
|-----|---------|
| (none) | `list --active` |
| `init` | Step 1 |
| `validate` | Step 2 |
| `list` | Step 3 |
| `show` | Step 4 |
| `add` | Step 5 |
| `remove` | Step 6 |
| `disable` | Step 7 |
| `enable` | Step 7 |
| `explain` | Step 8 |

Any unknown subcommand: print the subcommand table and exit.

---

## Step 1: `init`

Create `.ruby-upgrade-toolkit/rules.yml` with a starter template.

### 1a. Guard against overwrite

```bash
test -f .ruby-upgrade-toolkit/rules.yml && echo EXISTS
```

If the file exists, print and exit:

```
.ruby-upgrade-toolkit/rules.yml already exists.
Use /ruby-upgrade-toolkit:rules list to see active rules,
or /ruby-upgrade-toolkit:rules validate to check it.
```

### 1b. Create the directory

```bash
mkdir -p .ruby-upgrade-toolkit
```

### 1c. Copy the starter template

Read the file at `$CLAUDE_PLUGIN_ROOT/skills/rules/references/starter-template.yml`
and write its contents verbatim to `.ruby-upgrade-toolkit/rules.yml`.

### 1d. Announce

```
✓ Created .ruby-upgrade-toolkit/rules.yml with commented examples of all 8 rule types.

All examples are disabled by default (enabled: false). Edit the file or use
`/ruby-upgrade-toolkit:rules enable <id>` to activate any you want.

Next:
  /ruby-upgrade-toolkit:rules list --all     # see every example
  /ruby-upgrade-toolkit:rules validate       # schema-check
  /ruby-upgrade-toolkit:rules add gem-swap   # add your own rule interactively
```

---

## Step 2: `validate`

Run the full validation pipeline from the engine reference.

### 2a. Load and parse

Apply the "Load" section from `rules-engine.md`. If the file is missing,
print:

```
No .ruby-upgrade-toolkit/rules.yml found.
Run /ruby-upgrade-toolkit:rules init to create one.
```

Exit 0 (missing file is not an error — the toolkit behaves correctly without
one).

### 2b. Schema check

Apply the "Schema check" and "Conflict detection" sections from
`rules-engine.md`. Collect all findings with severity `error` | `warning` | `info`.

### 2c. Preflight check (credentials)

For any rule with a `source.credentials_env`, verify the env var is set and
non-empty. Missing credentials are `warning` (not `error`) here — at
`/validate` time the file may be authored before the env var is configured.
(At `audit`/`upgrade` preflight time they become `error`.)

### 2d. Report

```
.ruby-upgrade-toolkit/rules.yml — Validation Report

Schema: OK (N rules, M active, K disabled)

Errors: 0
Warnings: 2
  - [devise-pin] constraint '~> 4.9' has no effect on swap target (phantomjs-to-selenium replaces the gem)
  - [reek-gate] credentials_env 'BUNDLE_REEK__CO' is not currently set; will need to be set before /upgrade runs
Info: 0

Exit: 0 (no errors)
```

On any error, exit non-zero so CI can gate on this. On warnings only, exit 0.

---

## Step 3: `list`

Flag: `--all` includes disabled rules (default shows active only).

### 3a. Load

Apply the "Load" section from `rules-engine.md`. If the file doesn't exist,
print:

```
No .ruby-upgrade-toolkit/rules.yml found.
Run /ruby-upgrade-toolkit:rules init to scaffold one.
```

and exit.

### 3b. Render table

One row per rule. Columns: `id`, `type`, `target` (gem name, target name, or
pattern abbreviation), `enabled`, `when`.

```
Custom Rules (N active, K disabled)

ID                      TYPE                TARGET           ENABLED  WHEN
devise-pin              gem-constraint      devise           yes      all
phantomjs-to-selenium   gem-swap            phantomjs        yes      all
rails-lts-substitute    target-substitute   rails            yes      all
brakeman-gate           verification-gate   brakeman         yes      all
no-reek                 verification-gate   reek             no       all
load-defaults-6         policy-override     load_defaults    yes      rails-phases

Full schema: /ruby-upgrade-toolkit:rules show <id>
```

For `--all`, also include rules where `enabled: false`.

---

## Step 4: `show <id>`

### 4a. Load and find

Apply the "Load" section. If `<id>` not found:

```
No rule found with id '<id>'.
Active rules: devise-pin, phantomjs-to-selenium, rails-lts-substitute, brakeman-gate
```

### 4b. Render

Show:

1. The raw YAML block for the rule.
2. **Computed effects** — human-readable description of what this rule will
   do when applied, derived from the schema reference.
3. **Phases it will fire in** — given the current project state (detected
   Ruby/Rails versions) and the rule's `when` clause, list the exact phase
   names.
4. **Preflight status** — credentials env vars (if any), their set/unset
   state.
5. **Potential conflicts** — other rules in the file that touch the same
   gem/target, with their resolution (who wins on what).

Example:

```
─── rule: phantomjs-to-selenium ──────────────────────────────────────

Raw YAML:
  - id: phantomjs-to-selenium
    type: gem-swap
    from: phantomjs
    to:
      - { name: selenium-webdriver, constraint: '~> 4.0' }
      - { name: webdrivers, constraint: '~> 5.0' }
    code_transforms:
      - pattern: "Capybara.javascript_driver = :poltergeist"
        replacement: "Capybara.javascript_driver = :selenium_chrome_headless"
    description: "Replace phantomjs with selenium + headless chromium"

Computed effects:
  - Remove 'phantomjs' from Gemfile
  - Add 'selenium-webdriver ~> 4.0' and 'webdrivers ~> 5.0' to Gemfile
  - Rewrite 1 pattern in application code (literal match)

Will fire in phases (current: Ruby 3.2.4, Rails 6.1):
  - Ruby Phase 2: Ruby 3.3.1 (first phase that runs apply steps)

Preflight: no private gem source required ✓

Conflicts: none

─────────────────────────────────────────────────────────────────────
```

---

## Step 5: `add <type>`

Interactive Q&A authoring. `<type>` must be one of the eight rule types. If
missing or invalid, print the list of types and exit.

### 5a. Look up field requirements

Load the "Field schema per type" section from `schema.md`. Collect the
required and optional fields for the given `<type>`.

### 5b. Run the Q&A

For each required field, ask one question. For optional fields, ask
"<field>? (y/N)" and branch on answer. For enum fields, present numbered
choices.

**Type-specific prompts** — see the "Authoring prompts" section of
`schema.md`. Every type has a canonical question set documented there.
Follow it exactly so authored rules are consistent.

**Generating the id.** After collecting fields, propose a default id derived
from type + targets (e.g., `gem-swap from=phantomjs` → `phantomjs-swap`).
Always let the user override. Check for collisions with existing IDs; if
collision, append `-2`, `-3`, etc. and re-ask for confirmation.

### 5c. Preview

Render the new rule as YAML. Show the diff against the current file
(conceptually: the new block will be appended under `rules:`).

### 5d. Validate before write

Run the same validation pipeline as `validate` against the in-memory
merged file (existing rules + new rule). If any errors, print them and
abort; the user can re-run `add` with corrections. Warnings are OK to
proceed but are shown.

### 5e. Write

Append the new rule to `rules.yml`. If the file doesn't exist yet, create
it with the minimal `version: 1` / `rules: []` skeleton first.

### 5f. Announce

```
✓ Added rule '<id>' to .ruby-upgrade-toolkit/rules.yml

Next:
  /ruby-upgrade-toolkit:rules show <id>      # verify
  /ruby-upgrade-toolkit:rules explain        # see which phases it will fire in
```

---

## Step 6: `remove <id>`

### 6a. Load and find

If not found, print the same "No rule found" message as `show`.

### 6b. Preview

Show the rule's YAML block and a one-line summary of what will be removed.
Explicitly warn if this rule is `enabled: true` and is the only one of its
type (e.g., removing the sole `target-substitute` for `rails` will restore
mainline Rails upgrade behavior).

### 6c. Confirm

```
Remove rule '<id>'? This cannot be undone (use 'disable' for reversible deactivation). [y/N]
```

On `y`: delete the rule's entry from `rules.yml`, preserving comments and
surrounding structure. On `N`: print "Aborted. File unchanged." and exit.

### 6d. Announce

```
✓ Removed rule '<id>' from .ruby-upgrade-toolkit/rules.yml
```

---

## Step 7: `disable <id>` / `enable <id>`

### 7a. Load and find

Same as `show`.

### 7b. Flip the flag

Set `enabled: false` (for `disable`) or `enabled: true` (for `enable`) on
the matching rule. If the field is missing, add it. If the value is already
the target state, print:

```
Rule '<id>' is already <disabled|enabled>. No change.
```

and exit.

### 7c. Write and announce

```
✓ Rule '<id>' disabled. It will be ignored until re-enabled.
  /ruby-upgrade-toolkit:rules enable <id>
```

---

## Step 8: `explain`

Dry-run: show which rules will fire against the current project, which are
no-ops, and why.

### 8a. Load

Apply the "Load" section. If the file is missing, print the same message as
`list` and exit.

### 8b. Detect current state

```bash
ruby -v
cat .ruby-version 2>/dev/null
grep "^ruby " Gemfile 2>/dev/null
grep -A2 "RUBY VERSION" Gemfile.lock 2>/dev/null
bundle exec rails -v 2>/dev/null || true
```

Record `CURRENT_RUBY` and `CURRENT_RAILS`.

### 8c. For each active rule, determine what will happen

Apply the "Rule resolution" section from `rules-engine.md` to each rule
against the current state. Possible outcomes:

- **Will fire** — list the phases (e.g., "Ruby Phase 2", "all phases",
  "Rails Phase 1")
- **Won't fire (no-op)** — list the reason:
  - `gem-swap`: `from` gem is not in Gemfile
  - `code-transform`: `pattern` does not match any file content
  - `target-substitute`: target gem is not present
  - `verification-gate`: the `command` binary is not installed
  - `when` clause excludes current or future phases
- **Will fail preflight** — missing credentials env var (hard error at
  `/upgrade` time)

### 8d. Render

```
─── /ruby-upgrade-toolkit:rules explain ──────────────────────────────

Current state: Ruby 3.2.4, Rails 6.1.7

Active rules (4):

  [devise-pin]               gem-constraint
    Will fire: Ruby Phase 2, Rails Phase 1 (all apply phases)
    Effect: force devise >= 4.9 during bundle resolution

  [phantomjs-to-selenium]    gem-swap
    Will fire: Ruby Phase 2 (first apply phase)
    Matched: phantomjs found in Gemfile, 2 Capybara config sites match

  [rails-lts-substitute]     target-substitute
    Preflight: BUNDLE_RAILSLTS__COM is not set — /upgrade will fail

  [brakeman-gate]            verification-gate
    Will fire: verify step of every phase
    Command: 'bundle exec brakeman --no-pager --exit-on-warn'
    Binary check: OK (brakeman 6.1.2 found)

Disabled rules (1):
  [reek-gate]                verification-gate — re-enable with `/rules enable reek-gate`

─────────────────────────────────────────────────────────────────────
```

---

## Output conventions

All subcommands respect these:

1. **Mutating subcommands always preview + confirm.** Never silently write.
2. **Default to `list`** when invoked with no arguments, so a bare
   `/ruby-upgrade-toolkit:rules` gives an at-a-glance summary.
3. **Respect `enabled: false`**. Disabled rules are shown in `list --all`
   and `show <id>` but never influence `explain`, `audit`, `plan`, `fix`,
   `upgrade`, or `status`.
4. **Exit non-zero on `validate` errors.** Warnings exit 0. This makes
   `validate` usable in CI without further flags.
5. **Never print credential values.** Only the env var name, and whether
   it's set/unset.
