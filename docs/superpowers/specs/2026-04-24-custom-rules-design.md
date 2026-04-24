# Custom Rules for ruby-upgrade-toolkit — Design

**Status:** Approved design, pending implementation plan
**Date:** 2026-04-24
**Related commands:** `audit`, `plan`, `fix`, `upgrade`, `status` (existing); `rules` (new)

## Problem

Every real-world Ruby upgrade carries project-specific constraints the toolkit
cannot infer from the code alone. Examples:

- A gem must be pinned to (or above) a specific version for compliance or
  licensing reasons (`devise >= 4.9`).
- A legacy dependency must be swapped mid-upgrade for a modern replacement
  that also requires code changes (`phantomjs` → `selenium-webdriver` +
  headless chromium + Capybara config rewrite).
- The upgrade target itself is a paid/alternate distribution rather than the
  mainline gem — Rails LTS instead of mainline Rails, Sidekiq Pro from a
  private gem server instead of open-source Sidekiq.
- The team wants additional verification gates beyond the built-in
  RSpec/RuboCop checks — Brakeman must report zero warnings, Reek offenses
  must not exceed a baseline, a custom `bin/check-compliance.sh` must exit 0.
- The organization forbids certain gems outright, or pins intermediate Ruby
  patch versions to specific releases (`ruby 3.2.6`, not "latest 3.2").

Today, all of this must be handled by hand after running the toolkit — which
means it's easy to forget, inconsistent across projects, and invisible in the
audit/plan output. We need a first-class mechanism for expressing these rules,
one that the existing commands can pick up and act on automatically while
keeping the file readable as a standalone project policy document.

## Goals

1. Let users declare project-specific upgrade policies in a single
   version-controlled file.
2. Make those policies **first-class** in every command's output — if a rule
   changed behavior, the user can see it and verify it.
3. Stay **strictly additive**: a repo with no rules file behaves
   byte-identically to today.
4. Support real-world private gem sources (Rails LTS, Sidekiq Pro) without
   putting secrets in the rules file.
5. Offer a guided authoring UX so users don't have to memorize the schema,
   while keeping the file fully hand-editable.

## Non-goals (v1)

- Global or layered rule files (user-global `~/.ruby-upgrade-toolkit/rules.yml`,
  git-remote includes, shared organization rulebooks). Deferred to v2.
- Arbitrary Ruby DSL or evaluated rule code. YAML only.
- `phase-inject` with free-form scripts. Only parseable single-command actions
  in v1.
- Per-rule dry-run flag. The existing `explain` subcommand plus `fix`'s commit
  prompt already provide review gates.
- `diff` subcommand for comparing rule sets across projects. Useful but
  deferrable.
- Rule authoring UI beyond the `add` subcommand's Q&A flow.

## Conceptual model

Rules are **declarative overrides and extensions** that the existing commands
(`audit`, `plan`, `fix`, `upgrade`, `status`) consume as additional inputs.
They do not change the core algorithms of those commands; they **layer on
top**.

A rule can have one of three effects:

- **Constrain** — tighten or loosen what's allowed (gem version floors/caps,
  forbidden gems, policy knob overrides).
- **Substitute** — swap one target for another (gem → gem, or the upgrade
  target itself — mainline Rails → Rails LTS).
- **Extend** — add new gates, phases, or steps (Brakeman, Reek, custom
  verification commands, phase-injected shell commands).

Rules are **first-class in output**:

- `plan` annotates phase checklists with `[rule: <id>]` tags for rule-driven
  steps.
- `fix` lists rule outcomes in the proposed commit message.
- `status` reports rule-driven gates alongside built-in gates.
- `audit` has a dedicated "Custom Rules Impact" section.

**Backward compatibility guarantee:** a missing or empty `rules.yml` produces
exactly today's behavior. This is enforced by a regression test suite.

## File layout

**Path:** `.ruby-upgrade-toolkit/rules.yml` at the project root (not under
`.claude/`). The file's content is project policy — it encodes real
constraints about the Ruby app (gem pins, security gates, LTS subscriptions)
and must be reviewable/editable by team members who don't use Claude Code.
Precedent: `.rubocop.yml`, `.rspec`, `.bundle/config`, `.tool-versions` all
live at project root.

The `.ruby-upgrade-toolkit/` directory (rather than a single dotfile) leaves
room for sibling files in future versions — fixtures, credential templates,
per-phase override files — without another schema migration.

**Top-level structure:**

```yaml
version: 1                    # schema version; evolved independently of the plugin version
defaults:                     # optional: per-project policy knobs
  require_rubocop: true
  baseline_failures_allowed: 0
rules:                        # ordered list; order determines conflict resolution
  - id: …
    type: …
    …
```

**Common fields on every rule:**

- `id` — required, unique within the file, used by `list`/`show`/`remove`/`disable`
- `type` — required, one of the eight classes below
- `description` — human-readable rationale (encouraged, optional)
- `enabled` — defaults to `true`; `disable`/`enable` subcommands toggle it
- `when` — optional scoping, e.g. `{ phases: [ruby:3.3, rails:7.0] }` or `{ phases: [all] }` (default)
- `source` — on any rule that pulls a private gem, `{ url, credentials_env }` (no secret values stored in the file)

## Rule taxonomy (v1 vocabulary)

| `type` | Purpose | Key fields |
|---|---|---|
| `gem-constraint` | Pin/cap/floor/forbid a gem | `gem`, `constraint`, `mode: require|forbid` |
| `gem-swap` | Replace gem X with gem Y (may cascade to companion gems + code) | `from`, `to: [{name, constraint, source?}]`, `code_transforms?` |
| `target-substitute` | Swap the upgrade target itself (Rails → Rails LTS, Sidekiq → Sidekiq Pro as canonical) | `target`, `replacement: {gem, constraint, source?}` |
| `code-transform` | Pattern-based rewrite, run during a phase's apply step | `pattern`, `replacement`, `mode: literal|regex`, `files?` (glob) |
| `phase-inject` | Insert an imperative step into a phase | `phase`, `timing: before|after`, `action` (single shell command) |
| `verification-gate` | Additional GREEN gate (Brakeman, Reek, custom scripts) | `command`, `phases`, `timing: before|after`, `required: bool` |
| `policy-override` | Tweak toolkit defaults from a whitelisted set | `setting`, `value` |
| `intermediate-pin` | Pin a patch version during path computation | `ruby?` / `rails?`, `version` |

### Design notes on the taxonomy

**Why `target-substitute` is separate from `gem-swap`.** Rails LTS and
Sidekiq-Pro-as-canonical change what "target" means for `plan`'s path
computation. A mainline-Rails upgrade 6.1→7.0→7.1→8.0 becomes, under Rails
LTS, "stay on 6.1 with backported security patches." That's a fundamentally
different sequencer decision — it can't be modeled as a gem swap without
confusing the phase layout. `gem-swap` stays focused on "replace a dependency
during an upgrade"; `target-substitute` handles "this upgrade is aimed at a
different destination."

**Why `policy-override` has a whitelisted set of settings.** Allowing arbitrary
internal toggles via rules would create a surface where users can silently
disable safety rails they don't understand. v1 whitelist (subject to expansion):
`rubocop.enabled`, `baseline_failures_allowed`, `require_zero_deprecations`,
`require_zeitwerk_clean`. Anything outside the whitelist is a validation error.

**Why `code-transform` distinguishes `literal` vs `regex`.** The common case is
a literal string swap (`Capybara.javascript_driver = :poltergeist` →
`... = :selenium_chrome_headless`), which is both safer and easier to author.
Regex is an explicit opt-in, and `validate` runs a catastrophic-backtracking
check on the pattern at author time (safe-regex style).

**Why rule order matters within the file.** Conflicts are deterministic and
debuggable. `validate` surfaces overlaps at author time so ordering is a
conscious choice, not an accident.

## Credentials posture

Rules that reference a private gem source declare a `credentials_env` field —
the **name of an environment variable** the toolkit should check at preflight.
The actual secret is never stored in `rules.yml`.

```yaml
- id: sidekiq-to-sidekiq-pro
  type: gem-swap
  from: sidekiq
  to:
    - name: sidekiq-pro
      constraint: '~> 7.0'
      source:
        url: https://gems.contribsys.com/
        credentials_env: BUNDLE_GEMS__CONTRIBSYS__COM
```

At preflight (start of `audit`, `plan`, `fix`, `upgrade`), the toolkit:

1. Checks each referenced env var is set and non-empty.
2. On failure, emits a specific message: `BUNDLE_GEMS__CONTRIBSYS__COM is not
   set — set it in your shell or via 'bundle config gems.contribsys.com <creds>'
   before running upgrade.`
3. Never logs the env var's value.

This mirrors `bundler`'s own credential plumbing — no new secret-storage
machinery is introduced.

## Integration with existing commands

### `audit`

- Validates `rules.yml` (schema, duplicate IDs, unreachable conditions).
- Adds a "Custom Rules Impact" section listing each active rule, the phases it
  will touch, estimated incremental effort/risk, and preflight status.
- Fails fast if a `target-substitute` references an unreachable private source
  — an audit assuming Rails LTS is meaningless if the credentials can't fetch
  the gem.

### `plan`

- Path computation becomes rule-aware: `target-substitute` redirects the
  sequencer (e.g., "Rails 6.1 → Rails LTS 6.1" instead of "Rails 6.1 → 7.0 →
  …"); `intermediate-pin` overrides patch-level choices.
- Each phase's checklist is annotated. Built-in steps are unmarked; rule-driven
  steps get a `[rule: <id>]` tag:

  ```
  Rails Phase 1: 6.1 → 7.0
    - Update rails gem pin
    - Apply deprecation fixes
    - [rule: phantomjs-to-selenium] Swap phantomjs → selenium-webdriver + companion gems
    - [rule: phantomjs-to-selenium] Rewrite Capybara driver config (2 sites)
    - RSpec green + RuboCop clean
    - [rule: brakeman-gate] Brakeman: no warnings (required)
    - [rule: reek-gate] Reek: offenses ≤ baseline (advisory)
    - Checkpoint: status GREEN required
  ```

- The TodoWrite task list format is **unchanged**: one task per phase, same
  `Phase N — Ruby|Rails X.Y.Z: apply + verify + commit` format that `/fix next`
  already parses. Rules modify what happens *within* a phase, not the task
  structure. Exception: `phase-inject` with `as: standalone` promotes to its
  own task row if the user opts in. Default is inline.
- The Estimate Summary adds a "Rules contrib" column per phase, so the user
  can see which rules are moving effort/risk numbers.

### `fix`

- Apply order within a phase:
  1. `phase-inject` rules with `timing: before`.
  2. Built-in transforms (Ruby/Rails phase fixes).
  3. `code-transform` rules from `rules.yml`, in listed order.
  4. `gem-swap` rules (Gemfile edits + associated code transforms).
  5. `phase-inject` rules with `timing: after`.
- Verify order:
  1. `verification-gate` rules with `timing: before` (rare; useful when a check
     must observe pre-built-in state — e.g., "baseline offense count").
  2. Built-in gates (RSpec, RuboCop, deprecation count).
  3. `verification-gate` rules with `timing: after` (the common case —
     Brakeman, Reek, custom scripts), in declared order.
- A `required: true` gate that fails blocks GREEN the same way a RSpec failure
  does. `required: false` gates report and are itemized in the commit message
  as "advisory".
- The proposed commit message includes a "Custom rules applied" block:

  ```
  Custom rules applied:
  - [phantomjs-to-selenium] Swapped phantomjs → selenium-webdriver, webdrivers. Rewrote 2 Capybara config sites.
  - [brakeman-gate] Passed (0 warnings).
  - [reek-gate] 14 offenses (baseline: 14, advisory).
  ```

### `upgrade`

- Preflight (before the phase loop) verifies all rule prerequisites across all
  phases — credentials env vars, `target-substitute` reachability, `rules.yml`
  validity. Same posture as "all intermediate Ruby versions installed": one
  check, then proceed.
- The failure-recovery pause gains a fourth option:
  `D) Disable rule <id> and retry` — lets the user unblock the pipeline when
  a verification gate is the blocker, without hand-editing the file mid-run.

### `status`

- Dashboard adds a "Custom gates" section listing each `verification-gate`
  with its most recent result. Brakeman and Reek counts show up here the same
  way RuboCop offenses do today.

## The `/ruby-upgrade-toolkit:rules` command

One new top-level command with subcommands. Pure subcommands (`validate`,
`list`, `show`, `explain`) only read the file; mutating subcommands (`init`,
`add`, `remove`, `disable`, `enable`) write, show a diff, and confirm.

| Subcommand | Behavior |
|---|---|
| `init` | Creates `.ruby-upgrade-toolkit/rules.yml` with a commented starter template (one example per rule type). No-op if the file exists (suggests `validate`/`list`). |
| `validate` | Schema checks; reports unknown types, duplicate IDs, missing required fields, conflicting rules on the same gem, references to credentials env vars that aren't set. Exits non-zero on failure (CI-usable). |
| `list [--all]` | One-line-per-rule table: `id · type · target · enabled · when`. Default shows active only. |
| `show <id>` | Full rendered detail: source YAML, computed effects, phases the rule will fire in, preflight status. |
| `add <type>` | Guided Q&A authoring — asks class-specific questions, writes YAML, validates, shows diff, confirms. |
| `remove <id>` | Deletes the rule. Confirms with a diff preview. |
| `disable <id>` / `enable <id>` | Flips the `enabled` flag. Cheap reversible toggle without deleting. |
| `explain` | Dry-run against the current project: lists which rules will fire in which phases this run, which are no-ops, and why. The debugging subcommand. |
| (deferred) `diff <file-a> <file-b>` | Compare two rule sets. v1.1. |

**Default behavior with no subcommand:** `list --active` plus a summary line.

**Relationship to direct editing:** the command surface is a **convenience
layer** over the file, not a replacement. Power users edit `rules.yml` by hand;
`validate` catches schema mistakes either way. This matters because rules will
be reviewed and edited in PRs like any other config.

### Example authoring session (phantomjs → selenium)

```
$ /ruby-upgrade-toolkit:rules add gem-swap

What gem are you replacing? phantomjs
What gem (or gems) are you replacing it with?
  1) selenium-webdriver ~> 4.0
  Add another? (y/N) y
  2) webdrivers ~> 5.0
  Add another? (y/N) n
Private gem source? (y/N) n
Any code transformations to bundle with this swap? (y/N) y
  Pattern: Capybara.javascript_driver = :poltergeist
  Replacement: Capybara.javascript_driver = :selenium_chrome_headless
  Another? (y/N) n
Apply to which phases? [all / ruby-only / rails-only / specific]: all
Rule id (default: phantomjs-to-selenium): ⏎

Preview:
  + - id: phantomjs-to-selenium
  +   type: gem-swap
  +   from: phantomjs
  +   to:
  +     - { name: selenium-webdriver, constraint: '~> 4.0' }
  +     - { name: webdrivers, constraint: '~> 5.0' }
  +   code_transforms:
  +     - pattern: "Capybara.javascript_driver = :poltergeist"
  +       replacement: "Capybara.javascript_driver = :selenium_chrome_headless"
  +   when: { phases: [all] }
  +   description: "Replace phantomjs with selenium + headless chromium"

Validate → OK (no conflicts). Write to .ruby-upgrade-toolkit/rules.yml? [y/N]
```

## Conflicts and precedence

- **Within a file, order matters.** When two rules target the same gem, the
  later one wins. `validate` surfaces overlaps as warnings at author time so
  order is conscious.
- **`target-substitute` is exclusive on its target.** Two rules substituting
  the Rails target is a validation error.
- **`gem-constraint` + `gem-swap` on the same gem** is allowed; the constraint
  applies to the swap target if named there, otherwise a warning notes the
  constraint has no effect.
- **`verification-gate`s never conflict** — they are additive and run in
  declared order.
- **Built-in behavior always runs first**; rules layer on top. A
  `policy-override` that suppresses built-in behavior is limited to a fixed
  whitelist to prevent accidental disablement of safety rails.

## Safety model

**Pattern safety for `code-transform`:**

- `mode: literal` (default) — exact string match, no regex interpretation. Safe
  by construction.
- `mode: regex` — explicit opt-in. `validate` runs a catastrophic-backtracking
  check at author time.
- Both modes go through the same dry-run/review loop as the existing `fix`
  skill's built-in transforms: diffs shown before application, suite must stay
  green, `vendor/` is off-limits (enforced by the existing `block-vendor`
  hook).

**Command safety for `phase-inject` / `verification-gate`:**

- `command` strings in v1 must be a single parseable invocation (bundler,
  rake, or a shell script with no unescaped pipes/metacharacters). Full script
  injection is deferred to v2 behind an explicit `command_type: script` field.
- Commands inherit the project's environment but cannot modify it.
- Stdout/stderr are captured and surfaced in fix output; exit code 0 = pass,
  non-zero = fail.

## Testing strategy

- **Unit:** YAML schema validator, per-class rule parsers, conflict detector,
  preflight checker, pattern-safety check.
- **Integration:** fixture Rails repo with a sample `rules.yml` exercising
  every rule type; snapshot-test `audit`/`plan`/`fix`/`upgrade` output.
- **Golden:** the starter template from `rules init` is part of the snapshot
  tests — `init` output must stay valid against the current schema.
- **No-rules baseline:** every existing command regression-tested against a
  repo with no `rules.yml` to guarantee byte-identical behavior.

## Rollout

- v1 lands as a minor version bump (0.5.0). No breaking change — the feature
  is strictly additive.
- README gains a "Custom Rules" section with a worked example per rule class.
- Existing workflow examples (Scenarios 0–3) stay unchanged; a new Scenario 4
  demonstrates a Rails-LTS substitution with private credentials.

## Open questions (tracked for v1 implementation)

1. Exact shape of `policy-override`'s whitelist — start with a small set and
   grow on demand.
2. Whether `explain` should run preflight or only static analysis. Leaning
   static (fast, no network).
3. Whether `remove` should archive to a `.ruby-upgrade-toolkit/removed/` folder
   for audit trail, or hard-delete. Leaning hard-delete; git is the audit
   trail.

These will be resolved during implementation planning.
