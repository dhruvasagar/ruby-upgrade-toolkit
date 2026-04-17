---
name: Upgrade Orchestrator
description: Use when the user runs /ruby-upgrade-toolkit:upgrade or wants a fully automated Ruby/Rails upgrade pipeline. Orchestrates a phased upgrade by delegating per-phase execution to the fix skill and verification to the status skill. Keeps a live task list, pauses on RED verification, and lets the user continue, retry, or abort. Accepts ruby:X.Y.Z and optional rails:X.Y arguments.
argument-hint: "ruby:X.Y.Z [rails:X.Y]"
allowed-tools: Read, Edit, Bash, Glob, Grep, TodoWrite
version: 0.4.0
---

# Upgrade Orchestrator

Run a fully automated, phased Ruby (and optionally Rails) upgrade from start to finish.

**Architecture.** Upgrade is a thin orchestrator. It owns prerequisite checks (baseline, branch, Ruby installs), the phase loop, banners, the Failure Protocol, and the Final infra checklist. Everything else is delegated:

- **`plan/SKILL.md`** creates the TodoWrite task list — the single shared source of "what phases remain" for both manual and orchestrated flows. Upgrade runs plan at the start and never builds its own list.
- **`fix/SKILL.md`** owns the complete per-phase flow: apply → iterate to green → verify → prompt for commit → tick off the task. Upgrade drives it by repeatedly invoking `/ruby-upgrade-toolkit:fix next`.
- **`status/SKILL.md`** is loaded by fix during its verification step; upgrade does not run status directly for per-phase gating.
- Shared reference data (Ruby↔Rails compatibility matrix, upgrade paths, verification-suite bash) lives in `skills/rails-upgrade-guide/references/`.

**Manual mode equivalence.** Because upgrade drives fix through the same `/fix next` invocation a user would type, the manual workflow (`/plan` once, then iterate `/fix next`) produces identical behaviour to `/upgrade`. The only thing upgrade adds is the pre-loop prerequisite checks, the automatic loop, and the post-loop infra check — the per-phase work is byte-identical.

**Auto-advancement.** Once fix completes a phase with a successful commit (user approved at fix's commit prompt), upgrade moves to the next task automatically — no separate "continue?" prompt between phases. The user's checkpoint is the per-phase commit confirmation inside fix. If the user declines the commit, upgrade pauses and asks whether to continue on a dirty tree or abort.

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

## Step 4: Delegate Task List Creation to Plan

Load `$CLAUDE_PLUGIN_ROOT/skills/plan/SKILL.md` and run it with the same `ruby:<TARGET_RUBY> [rails:<TARGET_RAILS>]` arguments. Plan generates the Markdown roadmap (with estimates) AND creates the TodoWrite task list — upgrade does not build its own list and never appends to plan's list.

The resulting task list has this shape:

```
Phase 1 — Ruby X.Y.Z: apply + verify + commit
Phase 2 — Ruby X.Y.Z: apply + verify + commit
...
Phase N — Rails X.Y: apply + verify + commit
Final — Infra checks (CI/CD, Dockerfile) + checklist
```

Print a summary banner before starting the loop:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ruby Upgrade Orchestrator
Ruby:  CURRENT_RUBY → TARGET_RUBY
Rails: CURRENT_RAILS → TARGET_RAILS  (or "Ruby only")
Path:  [list intermediate steps if multi-step]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task list created by /plan. Running prerequisites next.
```

## Step 5: Prerequisites (upgrade-owned, not in the task list)

These checks are upgrade-specific orchestration — they do not appear as tasks in plan's list, and manual users who run `/plan + /fix next` skip them (or do equivalents on their own).

### 5a. Test suite baseline

Run the "Test suite — full run" and "Test suite — failure count" blocks from `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/verification-suite.md`.

Record `BASELINE_FAILURES`. If > 0, report:

```
⚠️  Pre-existing failures detected: N failures before upgrade begins.
    These are NOT caused by the upgrade and will not be fixed automatically.
```

Do not abort — continue.

### 5b. Intermediate Ruby versions installed (multi-step only)

If the upgrade path crosses more than one Ruby minor version, verify each intermediate version is already installed:

```bash
rbenv versions 2>/dev/null || rvm list 2>/dev/null
```

If any intermediate Ruby version is missing, stop and list what needs to be installed, then the user re-runs `/upgrade`.

### 5c. Upgrade branch

```bash
git status --short
git branch --show-current
```

If already on an upgrade branch (e.g. `upgrade/ruby-*`), continue. Otherwise:

```
Recommended: create a dedicated branch before starting.
  git checkout -b upgrade/ruby-TARGET_RUBY

Proceed on current branch? [yes / no — I'll create the branch first]
```

Wait for confirmation before proceeding.

### 5d. RuboCop baseline

Run the "RuboCop — offense count (JSON)" block. Record `BASELINE_RUBOCOP`.

Print: `✓ Prerequisites complete — baseline recorded (N RSpec failures, N RuboCop offenses)`

---

## Step 6: Phase Loop

Loop until no fix-actionable tasks remain in the task list.

On each iteration:

1. **Check the task list.** Call `TodoWrite`/TaskList to find the first pending task. If none remain, break the loop and proceed to Step 7 (Final).
2. **If it's the "Final — Infra checks" task**, break the loop and proceed to Step 7 — upgrade executes Final directly, not via fix.
3. **If it's a Ruby task** (`Phase N — Ruby X.Y.Z: apply + verify + commit`):
   - Confirm the correct Ruby binary is active (`ruby -v`). If not, pause with the standard activation instruction and wait for `continue`.
   - Invoke `/ruby-upgrade-toolkit:fix next` — fix reads the same task list, picks up the same task, executes end-to-end (apply → iterate to green → verify → prompt for commit → tick off task on commit).
4. **If it's a Rails task** (`Phase N — Rails X.Y: apply + verify + commit`):
   - Invoke `/ruby-upgrade-toolkit:fix next` — no need to check Ruby (it's already at target).

**Outcomes from each fix invocation:**

- **Fix committed** (task ticked off automatically by fix's Step 8e) → loop continues to the next pending task with no "continue?" prompt. This is the auto-advancement the user expects from the orchestrated mode.
- **User chose "no" at fix's commit prompt** → task remains pending, working tree is dirty. Upgrade pauses:
  ```
  Phase completed verification but commit was declined.
  Reply "continue" to advance past this task (your working tree is dirty),
  or "abort" to stop the upgrade.
  ```
  On `continue`, manually tick the task off in the list and advance.
- **Fix exited RED** → invoke Failure Protocol (see bottom of this file).

Why upgrade doesn't load fix's SKILL.md directly: the `/fix next` slash-command invocation is what drives parsing, task resolution, and the commit prompt end-to-end. Calling it keeps manual and orchestrated flows truly identical — the same fix run the user would get if they typed `/fix next` themselves.

---

## Step 7: Final Verification

Mark the "Final — Infra checks" task as in progress.

Print:
```
━━━ Final — Infra checks ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/status/SKILL.md` and run it to produce the full health dashboard (test suite, deprecations, RuboCop, Zeitwerk, readiness tier).

Additionally run these cross-cutting infra checks that don't fit status's code-level scope:

```bash
# CI/CD files still referencing old Ruby
grep -rn "ruby-${CURRENT_RUBY}" .github/ .circleci/ Jenkinsfile .gitlab-ci.yml 2>/dev/null | head -10

# Dockerfiles still using old base image
grep -rn "ruby:${CURRENT_RUBY}" Dockerfile* docker-compose* 2>/dev/null | head -10
```

Surface any matches in the Final Summary as manual steps.

Mark the "Final — Infra checks" task complete in TodoWrite.

---

## Step 8: Final Summary

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
