---
name: Upgrade Orchestrator
description: Use when the user runs /ruby-upgrade-toolkit:upgrade or wants a fully automated Ruby/Rails upgrade pipeline. Orchestrates a phased upgrade by delegating per-phase execution to the fix skill and verification to the status skill. Keeps a live task list, pauses on RED verification, and lets the user continue, retry, or abort. Accepts ruby:X.Y.Z and optional rails:X.Y arguments.
argument-hint: "ruby:X.Y.Z [rails:X.Y]"
allowed-tools: Read, Edit, Bash, Glob, Grep, TodoWrite
version: 0.3.0
---

# Upgrade Orchestrator

Run a fully automated, phased Ruby (and optionally Rails) upgrade from start to finish.

**Architecture.** Upgrade is a pure orchestrator. It owns the task list, the multi-phase loop, banners, per-phase activation, the Failure Protocol, and the final infra checklist (CI/CD, Dockerfiles). Everything else is delegated:

- **`fix/SKILL.md`** owns the complete per-phase flow: apply changes → iterate to green → run verification → prompt the user for commit. Upgrade invokes fix per intermediate version with the appropriate arguments and lets it run end-to-end.
- **`status/SKILL.md`** is loaded by fix during its verification step — upgrade does not run status directly for per-phase gating.
- Shared reference data (Ruby↔Rails compatibility matrix, upgrade paths, verification-suite bash) lives in `skills/rails-upgrade-guide/references/`.

**Auto-advancement.** Once fix completes a phase with a successful commit (user approved at fix's commit prompt), upgrade moves to the next phase automatically — no separate "continue?" prompt between phases. The user's checkpoint is the per-phase commit confirmation inside fix. If the user declines the commit, upgrade pauses and asks whether to continue on a dirty tree or abort.

This keeps every piece of logic in exactly one place. If a fix pattern or a commit-message format changes, it changes in fix/SKILL.md and upgrade picks it up automatically.

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

Each Ruby phase has two sub-tasks: activate the Ruby binary, then delegate to fix (which applies, verifies, and commits). Each Rails phase has a single delegation task.

**Example: Ruby 2.7 → 3.3, Rails 6.1 → 8.0 (generates this exact list):**

```
Phase 0 — Prerequisites: test baseline + upgrade branch
Phase 1a — Ruby 3.0.7: activate
Phase 1b — Ruby 3.0.7: apply + verify + commit (via fix)
Phase 2a — Ruby 3.1.6: activate
Phase 2b — Ruby 3.1.6: apply + verify + commit (via fix)
Phase 3a — Ruby 3.2.4: activate
Phase 3b — Ruby 3.2.4: apply + verify + commit (via fix)
Phase 4a — Ruby 3.3.1: activate
Phase 4b — Ruby 3.3.1: apply + verify + commit (via fix)
Phase 5 — Rails 7.0: apply + verify + commit (via fix)
Phase 6 — Rails 7.1: apply + verify + commit (via fix)
Phase 7 — Rails 8.0: apply + verify + commit (via fix)
Phase 8 — Final verification: infra checks (CI/CD, Dockerfile) + manual checklist
```

**Single-step examples:**
- Ruby 3.2 → 3.3 only → phases 0, 1a/1b, 2 (final)
- Rails 7.0 → 8.0 only → phases 0, 1 (Rails 7.1), 2 (Rails 8.0), 3 (final)

Omit Rails phases entirely if no `rails:` argument was given. Number phases sequentially based on the actual path.

**Auto-advancement between phases:** once a phase's `fix` delegation returns successfully (commit made), upgrade proceeds to the next phase automatically — no "continue?" prompt between phases. The user's checkpoint is fix's per-phase commit confirmation, not a separate upgrade-level one. Only RED phases (verification failure inside fix) pause the loop — those route to upgrade's Failure Protocol.

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

Per-phase *execution* is delegated to the `fix` skill — including verification and the commit prompt. Upgrade orchestrates: activation confirmation, fix invocation, task-list updates, and Failure Protocol on RED.

### 6a. Activate target Ruby

Mark the current Ruby phase's "activate" task as in progress.

Print:
```
━━━ Phase Xa: Ruby X.Y.Z — activating ━━━
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

Wait for "continue" before proceeding. Mark "Phase Xa" complete in TodoWrite.

### 6b. Execute the phase via fix

Mark "Phase Xb — Ruby X.Y.Z: apply + verify + commit" as in progress.

Print:
```
━━━ Phase Xb: Ruby X.Y.Z — fix delegation ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/fix/SKILL.md` and execute its **full flow** (Steps 1 through 9) with arguments `ruby:<this_phase_target_ruby>` (no `rails:` on Ruby phases). Fix owns:

- Version pins (Step 2)
- Gem resolution (Step 3)
- Ruby code fixes (Step 4)
- Iterative RSpec + RuboCop green-up (Steps 6–7)
- Verification + commit prompt (Step 8)
- Summary (Step 9)

**When fix prompts the user for commit confirmation, that prompt is shown to the user** — this is the per-phase checkpoint. The user approves or edits the message; fix makes the commit.

Outcomes from fix:

- **Fix committed successfully** → mark "Phase Xb" complete in TodoWrite. Auto-advance to the next phase (next intermediate Ruby, or Step 7 for Rails, or Step 8 for final verification) **without asking the user**.
- **User chose "no" at fix's commit prompt** → working tree is dirty and uncommitted. Pause and print:
  ```
  Phase Xb completed verification but commit was declined.
  Reply "continue" to advance to the next phase (your working tree is dirty),
  or "abort" to stop the upgrade.
  ```
- **Fix exited RED** (Step 8 verification failed) → invoke Failure Protocol. Fix did not commit; the working tree holds the problematic changes for the user to inspect.

---

## Step 7: Rails Phase Loop (skip entirely if no `rails:` argument)

Per-phase execution is delegated to the `fix` skill — including verification and commit. For each intermediate Rails version:

Mark the current Rails phase's "apply + verify + commit" task as in progress.

Print:
```
━━━ Phase X: Rails X.Y — fix delegation ━━━
```

Load `$CLAUDE_PLUGIN_ROOT/skills/fix/SKILL.md` and execute its **full flow** (Steps 1 through 9) with arguments `ruby:<final_ruby> rails:<this_phase_target_rails>`. Fix's Steps 2–4 fast-exit because Ruby is already at target; Steps 5a–5f apply the Rails-side changes; Steps 6–9 verify, prompt for commit, and summarise.

User-input pauses inside fix (open redirect option A/B/C, HABTM migration confirmation, commit prompt) run within fix's flow. Upgrade's Failure Protocol only triggers when fix exits RED from its Step 8 verification.

Outcomes:

- **Fix committed** → mark phase complete. Auto-advance to next Rails phase or Step 8 — no "continue?" prompt.
- **User declined commit at fix prompt** → pause and ask: `continue` (dirty tree) or `abort`.
- **RED verification** → Failure Protocol.

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
