---
name: Upgrade Orchestrator
description: Use when the user runs /ruby-upgrade-toolkit:upgrade or wants a fully automated Ruby/Rails upgrade pipeline. Orchestrates a phased upgrade by delegating per-phase execution to the fix skill and verification to the status skill. Keeps a live task list, pauses on RED verification, and lets the user continue, retry, or abort. Accepts ruby:X.Y.Z and optional rails:X.Y arguments.
argument-hint: "ruby:X.Y.Z [rails:X.Y]"
allowed-tools: Read, Edit, Bash, Glob, Grep, TodoWrite
version: 0.2.0
---

# Upgrade Orchestrator

Run a fully automated, phased Ruby (and optionally Rails) upgrade from start to finish.

**Architecture.** Upgrade is a pure orchestrator — it owns the task list, phase loop, banners, verification gate, failure protocol, and final summary. Per-phase *execution* is delegated:

- **`fix/SKILL.md`** is the source of truth for how to apply a phase (version pins, gem updates, code fixes, Rails migrations). Upgrade invokes fix per intermediate version with the right arguments and instructs it which step range to run.
- **`status/SKILL.md`** is the source of truth for the verification gate. Upgrade runs status after each phase and interprets its readiness tier (GREEN / YELLOW / RED).
- Shared reference data (Ruby↔Rails compatibility matrix, upgrade paths, verification-suite bash) lives in `skills/rails-upgrade-guide/references/` — upgrade loads it the same way the other skills do.

This keeps every piece of logic in exactly one place. If a fix pattern changes, it changes in fix/SKILL.md and upgrade picks it up automatically.

Maintain a live task list so the user can see exactly what is done, what is in progress, and what is coming next. Pause and surface any failure clearly before asking whether to continue, retry, or abort.

## Argument Parsing

Extract from the user's arguments:
- `ruby:X.Y.Z` — required target Ruby version
- `rails:X.Y` — optional target Rails version (omit sections if not provided)

## Step 1: Detect Current Versions

```bash
ruby -v 2>/dev/null || true
cat .ruby-version 2>/dev/null
grep "^ruby " Gemfile 2>/dev/null
grep -A2 "RUBY VERSION" Gemfile.lock 2>/dev/null
bundle exec rails -v 2>/dev/null || true
grep "gem ['\"]rails['\"]" Gemfile 2>/dev/null
grep "^    rails " Gemfile.lock 2>/dev/null | head -1
git branch --show-current 2>/dev/null
```

Read `Gemfile` and `Gemfile.lock`. Record:
- `CURRENT_RUBY` — current active Ruby version
- `TARGET_RUBY` — from arguments
- `CURRENT_RAILS` — if Rails project (else "none")
- `TARGET_RAILS` — from arguments (else "none")

**Early exit:** If `CURRENT_RUBY == TARGET_RUBY` and (`TARGET_RAILS` is none OR `CURRENT_RAILS == TARGET_RAILS`), print:

```
Already at target versions (Ruby TARGET_RUBY / Rails TARGET_RAILS).
Nothing to do. Run /ruby-upgrade-toolkit:status to confirm readiness.
```

Then stop.

## Step 2: Validate Compatibility

If `rails:` argument given, load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/ruby-rails-compatibility.md` and apply its validation rules. On hard incompatibility, stop immediately using the reference's error template.

## Step 3: Determine Upgrade Path

Load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/upgrade-paths.md` and use its rules to compute the ordered list of intermediate Ruby (and Rails) versions between current and target. Each intermediate version becomes its own phase — the test suite must be green before moving to the next.

## Step 4: Build the Task List

Using `TodoWrite`, create the **full concrete task list** before any work begins. Generate one task per sub-phase, substituting the real version numbers from the upgrade path computed in Step 3.

**Example: Ruby 2.7 → 3.3, Rails 6.1 → 8.0 (generates this exact list):**

```
Phase 0 — Prerequisites: test baseline + upgrade branch
Phase 1a — Ruby 3.0.7: activate + version pins + gem updates
Phase 1b — Ruby 3.0.7: code fixes (keyword args, YAML, stdlib)
Phase 1c — Ruby 3.0.7: verify (RSpec + RuboCop + GREEN)
Phase 2a — Ruby 3.1.6: activate + version pins + gem updates
Phase 2b — Ruby 3.1.6: code fixes
Phase 2c — Ruby 3.1.6: verify (RSpec + RuboCop + GREEN)
Phase 3a — Ruby 3.2.4: activate + version pins + gem updates
Phase 3b — Ruby 3.2.4: code fixes
Phase 3c — Ruby 3.2.4: verify (RSpec + RuboCop + GREEN)
Phase 4a — Ruby 3.3.1: activate + version pins + gem updates
Phase 4b — Ruby 3.3.1: code fixes (it-parameter check)
Phase 4c — Ruby 3.3.1: verify (RSpec + RuboCop + GREEN)
Phase 5a — Rails 7.0: gem updates + bin/rails app:update
Phase 5b — Rails 7.0: deprecation fixes + framework defaults
Phase 5c — Rails 7.0: verify (RSpec + RuboCop + GREEN)
Phase 6a — Rails 7.1: gem updates + bin/rails app:update
Phase 6b — Rails 7.1: deprecation fixes + framework defaults
Phase 6c — Rails 7.1: verify (RSpec + RuboCop + GREEN)
Phase 7a — Rails 8.0: gem updates + bin/rails app:update
Phase 7b — Rails 8.0: deprecation fixes + framework defaults
Phase 7c — Rails 8.0: verify (RSpec + RuboCop + GREEN)
Phase 8 — Final verification: full suite + deprecation count + manual checklist
```

**Single-step examples:**
- Ruby 3.2 → 3.3 only → phases 0, 1a/1b/1c, 2 (final)
- Rails 7.0 → 8.0 only → phases 0, 1a/1b/1c (7.1), 2a/2b/2c (8.0), 3 (final)

Omit Rails phases entirely if no `rails:` argument was given. Number phases sequentially based on the actual path — do not use placeholder letters like "X.Y".

Print a summary banner before starting:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ruby Upgrade Orchestrator
Ruby:  CURRENT_RUBY → TARGET_RUBY
Rails: CURRENT_RAILS → TARGET_RAILS  (or "Ruby only")
Path:  [list intermediate steps if multi-step]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task list created. Starting Phase 0.
```

## Step 5: Phase 0 — Prerequisites

Mark "Phase 0" as in progress in TodoWrite.

### 5a. Test suite baseline

Run the "Test suite — full run" and "Test suite — failure count" blocks from `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/verification-suite.md`.

Record `BASELINE_FAILURES`. If > 0, report them clearly:

```
⚠️  Pre-existing failures detected: N failures before upgrade begins.
    These are NOT caused by the upgrade and will not be fixed automatically.
    They will be tracked separately throughout the process.
```

Do not abort — continue with the baseline recorded.

### 5b. Intermediate Ruby versions installed (multi-step only)

If the upgrade path crosses more than one Ruby minor version, verify each intermediate version is already installed before starting any work:

```bash
# For each intermediate Ruby version in the path:
rbenv versions 2>/dev/null || rvm list 2>/dev/null
```

If any intermediate Ruby version is missing, stop immediately and list what needs to be installed:

```
⛔ Missing Ruby versions required for this upgrade path.
   Please install them before starting:

     rbenv install 3.0.7
     rbenv install 3.1.6
     rbenv install 3.2.4
     rbenv install 3.3.1

   Then re-run /ruby-upgrade-toolkit:upgrade ruby:TARGET_RUBY [rails:TARGET_RAILS]
```

Do not proceed until all required versions are present.

### 5c. Upgrade branch

```bash
git status --short
git branch --show-current
```

If already on an upgrade branch (e.g. `upgrade/ruby-*`), continue. Otherwise, suggest:

```
Recommended: create a dedicated branch before starting.
  git checkout -b upgrade/ruby-TARGET_RUBY

Proceed on current branch? [yes / no — I'll create the branch first]
```

Wait for confirmation before proceeding.

### 5d. RuboCop baseline

Run the "RuboCop — offense count (JSON)" block from the verification suite reference. Record `BASELINE_RUBOCOP`.

Mark "Phase 0" complete in TodoWrite. Print:
```
✓ Phase 0 complete — baseline recorded (N RSpec failures, N RuboCop offenses)
```

---

## Step 6: Ruby Phase Loop (repeat for each intermediate Ruby version)

Per-phase *execution* is delegated to the `fix` skill. Upgrade orchestrates: activation confirmation, fix invocation with correct arguments, verification gate via `status`, and task-list updates.

### 6a. Activate target Ruby

Mark the current Ruby phase's "activate + version pins + gem updates" task as in progress.

Print:
```
━━━ Phase Xa: Ruby X.Y.Z — activating + fix delegation ━━━
```

Confirm the correct Ruby binary is active:

```bash
ruby -v
```

If the active Ruby is NOT this phase's target version, pause:

```
⛔ Ruby X.Y.Z is not active. Please activate it:
     rbenv local X.Y.Z
   or:
     rvm use X.Y.Z
   Then reply "continue" to resume from here.
```

Wait for "continue" before proceeding.

### 6b. Execute the phase via fix

Load `$CLAUDE_PLUGIN_ROOT/skills/fix/SKILL.md` and execute **Steps 1 through 4 only** with arguments `ruby:<this_phase_target_ruby>` (no `rails:` on Ruby phases). This applies:

- Ruby version pins (fix Step 2)
- Gem dependency resolution (fix Step 3)
- Ruby version-specific code fixes (fix Step 4)

**Stop at the end of fix Step 4.** Do NOT run fix Step 5 (Rails), Step 6 (iterative RSpec), Step 7 (iterative RuboCop), or Step 8 (summary) — upgrade owns its own verification gate and multi-phase summary.

Surface notable actions from fix as they happen (gem updates, code fix counts, file-level test runs) so the user can follow progress.

Mark "Phase Xa" and "Phase Xb" complete in TodoWrite once fix reports Steps 2–4 done.

### 6c. Verify Ruby phase

Mark "Phase Xc — Ruby X.Y.Z: verify" as in progress.

Print:
```
━━━ Phase Xc: verification ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/status/SKILL.md` and run it. Interpret the readiness tier against this upgrade run's `BASELINE_FAILURES` (pre-existing failures count as baseline, not regressions).

Print the one-line result:
```
  Ruby: X.Y.Z ✓
  RSpec: N examples, N failures (N pre-existing, 0 new) ✓
  RuboCop: N offenses ✓
  Status: GREEN ✓
```

Decision:
- **GREEN** → mark phase complete, continue to the next intermediate Ruby (or advance to Rails phases / final verification).
- **YELLOW** → log warnings to the final-summary buffer, continue to next phase.
- **RED** → invoke Failure Protocol (bottom of this file).

Mark "Phase Xc" complete in TodoWrite.

---

## Step 7: Rails Phase Loop (skip entirely if no `rails:` argument)

Per-phase *execution* is delegated to the `fix` skill. For each intermediate Rails version:

### 7a. Execute the phase via fix

Mark the current Rails phase's "gem updates + app:update" task as in progress.

Print:
```
━━━ Phase Xa: Rails X.Y — fix delegation ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/fix/SKILL.md` and execute **Steps 5a through 5f only** with arguments `ruby:<final_ruby> rails:<this_phase_target_rails>`. Fix's earlier steps (2–4) will fast-exit because Ruby is already at target. The Rails-side steps apply:

- Rails gem update + `bin/rails app:update` (fix Steps 5a–5b)
- Framework defaults (fix Step 5c)
- Deprecation fixes (fix Step 5d — includes the pause-for-user flow for open redirects and HABTM)
- Turbolinks → Turbo migration if upgrading to Rails 7+ (fix Step 5e)
- RuboCop target version bump (fix Step 5f)

**Stop at the end of fix Step 5f.** Do NOT run fix Steps 6–8.

Any user-input pauses inside fix (open redirect option A/B/C, HABTM migration confirmation) run within fix's flow — upgrade's Failure Protocol is separate and only triggers on phase verification RED.

Mark "Phase Xa" and "Phase Xb" complete in TodoWrite once fix reports Step 5 done.

### 7b. Verify Rails phase

Mark "Phase Xc — Rails X.Y: verify" as in progress.

Print:
```
━━━ Phase Xc: verification ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/status/SKILL.md` and run it. Additionally confirm Rails version is live:

```bash
bundle exec rails runner "puts Rails.version" 2>&1
```

Interpret the readiness tier against `BASELINE_FAILURES`. RED → Failure Protocol.

Mark "Phase Xc" complete in TodoWrite.

---

## Step 8: Final Verification

Mark "Final verification" as in progress.

Print:
```
━━━ Final verification ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/status/SKILL.md` and run it to produce the full health dashboard (test suite, deprecations, RuboCop, Zeitwerk, readiness tier).

Upgrade additionally owns these cross-cutting infra checks that don't fit status's code-level scope:

```bash
# CI/CD files still referencing old Ruby
grep -rn "ruby-${CURRENT_RUBY}" .github/ .circleci/ Jenkinsfile .gitlab-ci.yml 2>/dev/null | head -10

# Dockerfiles still using old base image
grep -rn "ruby:${CURRENT_RUBY}" Dockerfile* docker-compose* 2>/dev/null | head -10
```

Surface any matches in the Final Summary as manual steps.

Mark "Final verification" complete in TodoWrite.

---

## Step 9: Final Summary

Print the complete summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Upgrade Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ruby:  CURRENT_RUBY → TARGET_RUBY ✓
Rails: CURRENT_RAILS → TARGET_RAILS ✓  (or "not upgraded")

RSpec
  Before: N failures (N pre-existing)
  After:  N failures (all pre-existing — 0 new)

RuboCop
  Before: N offenses
  After:  N offenses

Gems updated: [list]
Files changed: N

━━━ Manual steps still required ━━━
• CI/CD files still referencing Ruby CURRENT_RUBY:
    [list paths]
• Dockerfiles still using old base image:
    [list paths]
• Pre-existing RSpec failures (fix independently): N
• Complex patterns deferred for user review:
    [list any HABTM, open redirect, or other deferred items]

Run /ruby-upgrade-toolkit:status at any time to recheck readiness.
```

---

## Failure Protocol

Invoke this whenever a phase verification returns RED (new failures above baseline), or a fix introduces a regression that cannot be auto-corrected in one retry.

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⛔ UPGRADE PAUSED — Phase [name] did not pass verification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Failures introduced by this phase: N (above the N pre-existing baseline)

[Print the full RSpec failure output for each new failure — file, line, error message, backtrace]

━━━ What you can do ━━━

  A) Investigate and fix  — resolve the failures yourself, then reply "continue"
                             to resume from the verification step of this phase.

  B) Retry this phase     — reply "retry phase [name]" to re-run just this phase's
                             fixes from the beginning (useful if a fix was incomplete).

  C) Abort                — reply "abort" to stop here. All changes made so far
                             are preserved — nothing is rolled back.

Waiting for your decision...
```

**When the user replies "continue":**
Re-run the verification step for the current phase. If now GREEN, mark the phase complete and proceed to the next phase.

**When the user replies "retry phase [name]":**
Re-run that phase's fix step (not the version pin step — only the code/gem fix step) from the beginning, then re-verify.

**When the user replies "abort":**
Print a summary of what was completed and what was not. Do not roll back any changes. Exit.
