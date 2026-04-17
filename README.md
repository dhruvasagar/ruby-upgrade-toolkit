# ruby-upgrade-toolkit

A Claude Code plugin for upgrading Ruby projects safely — including Ruby on Rails apps. Supports any Ruby version upgrade (2.7→3.x and beyond) and any Rails version upgrade (5→8), separately or together.

## How It Works

The plugin gives Claude a structured, repeatable methodology for Ruby and Rails upgrades. The five commands compose — use as many or as few as you need.

### Mode 1: Fully automated

```
/ruby-upgrade-toolkit:upgrade ruby:X.Y.Z [rails:X.Y]
```

One command runs everything: detects versions, validates compatibility, computes the full upgrade path (including intermediate versions), creates a live task list, applies fixes phase by phase, verifies after each phase, and pauses with a recovery menu if anything fails.

**Use this when** you want to move quickly and trust Claude to sequence and execute the work.

### Mode 2: Review first, then automate (recommended for first-time upgrades)

```
/ruby-upgrade-toolkit:audit ruby:X.Y.Z [rails:X.Y]   # understand the scope
/ruby-upgrade-toolkit:plan ruby:X.Y.Z [rails:X.Y]    # review the phase sequence
/ruby-upgrade-toolkit:upgrade ruby:X.Y.Z [rails:X.Y] # execute the plan
```

`audit` surfaces breaking changes and gives an effort estimate before touching any code. `plan` shows exactly which phases will run, in what order, and — in its Estimate Summary — the effort, risk, blast radius, and confidence for each phase so you can sanity-check scope and sequencing. Once you're comfortable with the plan, `upgrade` executes the same sequence automatically — no need to re-specify anything.

**Use this when** you're doing a major version jump, have a large codebase, or want to understand the scope before committing to execution.

### Mode 3: Fully manual (maximum control)

```
/ruby-upgrade-toolkit:audit ruby:X.Y.Z [rails:X.Y]   # read-only scan
/ruby-upgrade-toolkit:plan  ruby:X.Y.Z [rails:X.Y]   # roadmap + creates a task list
/ruby-upgrade-toolkit:fix   next                     # apply next pending phase; repeat
```

`plan` creates a TodoWrite task list (one task per phase); `fix next` reads the list, picks the first pending task, applies it, verifies, prompts you for commit, and ticks it off. Iterate `fix next` until the list is empty. You can also pass explicit args to `fix` to jump to a specific phase — useful when resuming or working out of order.

**Use this when** you want to inspect and approve changes phase by phase, apply fixes to a specific scope (`scope:path`), or resume a partially completed upgrade.

**Manual and automated share the same machinery.** `/upgrade` is literally `/plan` + a loop that invokes `/fix next` until the list is empty, plus some pre-loop prerequisite checks (branch, Ruby installs) and a post-loop Final infra check (CI/CD, Dockerfiles). The per-phase work is byte-identical.

**Why the order matters:**
- `audit` is read-only — zero risk, surfaces breaking changes and effort before touching anything
- `plan` sequences work correctly (Ruby phases before Rails phases, intermediate versions in the right order), quantifies each phase (effort, risk, blast radius, confidence), **and creates the task list that drives the rest of the workflow**
- `fix next` consumes the next pending task from the list; on successful commit it ticks the task off. Repeat until the list is empty.
- `status` is an on-demand dashboard — useful for a full health snapshot, though `fix`'s built-in verification is what gates the commit

## Installation

### Via Claude Code marketplace

Add the marketplace and install the plugin:

```
/plugin marketplace add dhruvasagar/ruby-upgrade-toolkit
/plugin install ruby-upgrade-toolkit@dhruvasagar
```

Or use the interactive UI: run `/plugin`, go to the **Discover** tab, search for `ruby-upgrade-toolkit`, and click Install.

### Local development

```bash
git clone https://github.com/dhruvasagar/ruby-upgrade-toolkit
```

Then add the cloned directory as a local marketplace and install:

```
/plugin marketplace add /path/to/ruby-upgrade-toolkit
/plugin install ruby-upgrade-toolkit
/reload-plugins
```

## Updating

### Marketplace install

Uninstall and reinstall to get the latest version:

```
/plugin uninstall ruby-upgrade-toolkit@dhruvasagar
/plugin install ruby-upgrade-toolkit@dhruvasagar
```

Then reload without restarting Claude Code:

```
/reload-plugins
```

To enable auto-updates for this marketplace, run `/plugin`, go to the **Marketplaces** tab, select `dhruvasagar`, and toggle **Enable auto-update**. When an update is detected at startup, Claude Code will prompt you to run `/reload-plugins`.

### Local install

Pull the latest changes and reload:

```bash
cd /path/to/ruby-upgrade-toolkit
git pull
```

```
/reload-plugins
```

## Command Reference

All commands are namespaced under `/ruby-upgrade-toolkit:` to avoid conflicts with other plugins.

### `/ruby-upgrade-toolkit:upgrade ruby:X.Y.Z [rails:X.Y]`

**The recommended starting point.** Runs the full upgrade pipeline automatically with per-phase commit checkpoints. Equivalent to running `/plan` once and then iterating `/fix next` until the task list is empty, with prerequisite and final infra checks bolted on either side.

What it does:
1. Detects current versions, validates Ruby ↔ Rails compatibility, computes the full upgrade path
2. **Delegates to `/plan`** to produce the roadmap + estimates and create the TodoWrite task list
3. Checks all intermediate Ruby versions are installed (stops early if not)
4. Confirms a baseline: test failures and RuboCop offenses before any changes
5. Checks/creates an upgrade branch if needed
6. Loops: invokes `/fix next` — which picks the next pending task, applies changes, iterates to green, verifies, **prompts for a git commit with a detailed message**, and ticks the task off on commit
7. Auto-advances between phases once the commit lands — no "continue?" prompt
8. After all apply-phase tasks are done, runs Final infra checks (CI/CD, Dockerfiles) and produces a summary
9. On verification failure: pauses with full error output and three options — investigate+continue, retry the phase, or abort (no rollback; working tree holds the problematic changes)

```bash
# Automated Ruby-only upgrade
/ruby-upgrade-toolkit:upgrade ruby:3.3.1

# Automated Ruby + Rails upgrade
/ruby-upgrade-toolkit:upgrade ruby:3.3.1 rails:8.0
```

Intermediate Ruby versions must be installed via rbenv/rvm before running. The command will tell you exactly which ones are missing if any are absent.

---

### `/ruby-upgrade-toolkit:audit ruby:X.Y.Z [rails:X.Y]`

Read-only pre-upgrade assessment. Run this first.

Surfaces: Ruby breaking changes for the target version, Rails deprecations (if Rails present), gem incompatibilities for both Ruby and Rails targets, migration safety issues, RuboCop TargetRubyVersion gap, and an effort estimate.

**Never modifies any file.**

```bash
# Ruby-only audit
/ruby-upgrade-toolkit:audit ruby:3.3.1

# Combined Ruby + Rails audit
/ruby-upgrade-toolkit:audit ruby:3.3.1 rails:8.0
```

### `/ruby-upgrade-toolkit:plan ruby:X.Y.Z [rails:X.Y]`

Generate a phased, project-specific upgrade roadmap **and** create the TodoWrite task list that drives `/fix next` and `/upgrade`. Detects current versions automatically.

Produces:
1. A Markdown plan with prerequisites, Ruby upgrade phases (one per intermediate version), Rails upgrade phases (if `rails:` given), and a final verification checklist.
2. An **Estimate Summary** — per-phase effort (hours), risk (LOW/MED/HIGH), blast radius (files, call sites, gems touched), and confidence level. Numbers are derived from concrete grep counts and `bundle outdated` results, never guessed; each total ships with the formula so you can audit or override it.
3. A **TodoWrite task list** — one task per apply-phase, in the canonical `Phase N — Ruby|Rails X.Y.Z: apply + verify + commit` format that `/fix next` parses. Re-running `/plan` overwrites the list (current repo state is authoritative).

```bash
# Ruby-only plan
/ruby-upgrade-toolkit:plan ruby:3.3.1

# Combined Ruby + Rails plan
/ruby-upgrade-toolkit:plan ruby:3.3.1 rails:8.0
```

### `/ruby-upgrade-toolkit:fix next | ruby:X.Y.Z [rails:X.Y] [scope:path]`

Apply one phase of upgrade changes. The primary execution command, usable in two modes:

**`/fix next`** — reads the task list created by `/plan`, picks the first pending task, parses the target from the task subject, and executes. On successful commit, ticks that task off the list. Best for iterating through a planned upgrade.

**`/fix ruby:X.Y.Z [rails:X.Y] [scope:path]`** — explicit target. Useful when resuming, jumping to a specific phase, or running fix without a plan. If the explicit args happen to match a pending task, fix still ticks it off on commit.

Either mode applies: `.ruby-version` and `Gemfile` pin updates, gem dependency updates, Ruby version-specific code fixes, Rails deprecation fixes (if `rails:` given), Rails config updates, iterative RSpec until green, iterative RuboCop until clean.

When the phase reaches GREEN (or YELLOW — tests pass, warnings remain), `fix` builds a detailed proposed commit message that itemises what changed (version pins, gem diffs, fix counts, verification results) and prompts you to `yes / edit / no`:

- **yes** — stages the tracked files and commits with the proposed message
- **edit** — you revise the message first, then it commits
- **no** — skips the commit; your working tree is left dirty for you to handle manually

On RED (new failures above baseline), `fix` exits without prompting and without committing — you inspect the failures and rerun.

The same prompt runs whether you call `/fix` directly or it's driven by `/upgrade`. When orchestrated by `/upgrade`, the post-commit auto-advance to the next phase is what differs; the commit confirmation itself is always shown.

Flags CI/CD pipeline files and Dockerfiles for manual update — never modifies them automatically.

```bash
# Typical manual flow — run /plan once, then iterate this:
/ruby-upgrade-toolkit:fix next

# Explicit target (ignores the task list)
/ruby-upgrade-toolkit:fix ruby:3.3.1

# Explicit target, Ruby + Rails
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0

# Fix a single file only (gem/pin changes still apply project-wide)
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/models/user.rb

# Fix a directory
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/controllers/
```

### `/ruby-upgrade-toolkit:status`

Current upgrade health dashboard. No arguments.

Reports: current vs. target versions, test suite pass/fail, deprecation warning count, Ruby warning count, RuboCop offense count, Zeitwerk status (Rails), and overall RED/YELLOW/GREEN readiness.

`fix` runs this internally before prompting for its per-phase commit, so the same tier is already gating the commit. Call `/status` directly when you want an on-demand snapshot outside the fix flow — e.g., to check health mid-session or after a manual edit.

```bash
/ruby-upgrade-toolkit:status
```

## Workflow Examples

Four complete walkthroughs below. Scenario 0 uses the automated `upgrade` command — the fastest path. Scenarios 1–3 use the manual `audit → plan → fix → status` loop for full control.

> **Rule of thumb:** `fix` runs verification and prompts for a commit before the phase "completes" — so the commit itself is the checkpoint. Only decline or hit RED if something actually looks wrong. You can still run `/status` any time for a full on-demand dashboard.

---

### Scenario 0: Automated upgrade (Ruby 3.1 → 3.3, Rails 7.0 → 7.2)

**Starting state:** Ruby 3.1.4, Rails 7.0.8. Two Ruby minor hops (3.1 → 3.2 → 3.3), two Rails minor hops (7.0 → 7.1 → 7.2).

Install required Ruby versions first (the command will tell you exactly which are missing if any):

```bash
rbenv install 3.2.4
rbenv install 3.3.1
```

Then run one command:

```
/ruby-upgrade-toolkit:upgrade ruby:3.3.1 rails:7.2
```

Claude delegates task list creation to `/plan`, runs prerequisite checks, and then loops through the tasks:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ruby Upgrade Orchestrator
Ruby:  3.1.4 → 3.3.1
Rails: 7.0.8 → 7.2
Path:  Ruby: 3.1 → 3.2 → 3.3 | Rails: 7.0 → 7.1 → 7.2
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task list created by /plan. Running prerequisites next.

☐ Phase 1 — Ruby 3.2.4: apply + verify + commit
☐ Phase 2 — Ruby 3.3.1: apply + verify + commit
☐ Phase 3 — Rails 7.1: apply + verify + commit
☐ Phase 4 — Rails 7.2: apply + verify + commit
☐ Final  — Infra checks (CI/CD, Dockerfile) + checklist
```

Upgrade then loops `/fix next` — each invocation picks the first pending task, runs the full apply → verify → commit flow, and ticks that task off. As each phase completes, its task is ticked off. Each phase ends with fix's commit prompt:

```
━━━ Phase verification: GREEN ━━━
chore(upgrade): ruby 3.2.4 phase
...
Commit this now? [yes / edit / no]
```

Answer `yes` (or `edit` then provide your own message) and the phase's changes land as a reviewable commit. Upgrade immediately moves to the next phase — no separate "continue?" prompt.

If a phase fails verification, the upgrade pauses (no commit is made):

```
⛔ UPGRADE PAUSED — Phase 1b: Ruby 3.2.4 did not pass verification

Failures introduced by this phase: 2 (above the 0 pre-existing baseline)

  1) UserSerializer#to_json raises on nil input
     Failure/Error: UserSerializer.new(nil).to_json
     NoMethodError: undefined method 'name' for nil

━━━ What you can do ━━━

  A) Investigate and fix — resolve the failures yourself, then reply "continue"
  B) Retry this phase   — reply "retry phase 1b" to re-run phase 1b's fixes
  C) Abort              — reply "abort" to stop here (working tree preserved)

Waiting for your decision...
```

Fix the issue in `app/serializers/user_serializer.rb`, then reply `continue`. Claude re-runs verification and proceeds automatically if green — surfacing the commit prompt for your approval before moving on.

---

### Scenario 1: Ruby-only upgrade (no Rails, 2.7 → 3.3)

**Starting state:** Ruby 2.7.8, no Rails, RSpec suite, 47 gems.

#### Step 1 — Audit (read-only, zero risk)

```
/ruby-upgrade-toolkit:audit ruby:3.3.1
```

Claude runs a full pre-upgrade scan and produces a findings report. Typical output:

```
# Ruby Upgrade Audit Report
Current: Ruby 2.7.8
Target:  Ruby 3.3.1
Upgrade Path: 2.7 → 3.0 → 3.1 → 3.2 → 3.3 (4 phases required)

## Test Suite Baseline
- Status: PASSING
- 312 examples, 0 failures

## Critical Issues
### Keyword Argument Mismatches (Ruby 3.0)
- 18 methods with **kwargs or opts={} patterns
- 34 call sites with potential hash/keyword mismatch
- Preview warnings from Ruby 2.7: 22 unique warning sites

### Unsafe YAML.load calls
- 3 occurrences: lib/config_loader.rb, lib/serializer.rb, config/initializers/legacy.rb

## Effort Estimate
Overall: Medium
- Keyword arg fixes: ~34 sites (automated with review)
- YAML fixes: 3 files (automated)
- RuboCop TargetRubyVersion gap: 2.7 → 3.3 (expect new cops)
```

Read the report carefully before proceeding. The 2.7→3.0 keyword argument change is the most impactful — it is a hard break, not a deprecation warning.

#### Step 2 — Plan

```
/ruby-upgrade-toolkit:plan ruby:3.3.1
```

Claude generates a phased roadmap specific to your project. It sequences intermediate versions correctly — you cannot jump from 2.7 directly to 3.3 safely. The plan output:

```
## Upgrade Roadmap: Ruby 2.7.8 → 3.3.1

### Estimate Summary
| Phase             | Effort | Risk | Blast radius           | Confidence |
|-------------------|--------|------|------------------------|------------|
| Phase 1: 2.7→3.0  | ~2.5h  | MED  | 37 sites, 3 files      | HIGH       |
| Phase 2: 3.0→3.1  | ~1h    | LOW  | 0 sites                | HIGH       |
| Phase 3: 3.1→3.2  | ~1h    | LOW  | 0 sites                | HIGH       |
| Phase 4: 3.2→3.3  | ~1h    | LOW  | 0 sites                | HIGH       |
| **Total**         | **~5.5h** | **MED** | 37 sites, 3 files | **HIGH**   |

Formulas:
- Phase 1 = 34 kwarg × 2min + 3 YAML × 2min + 1 hop × 60min = 134min ≈ 2.5h
- Phases 2–4 = 1 hop × 60min each = 1h each

### Prerequisites
- [ ] Install Ruby 3.0.7: rbenv install 3.0.7
- [ ] Install Ruby 3.1.6: rbenv install 3.1.6
- [ ] Install Ruby 3.2.4: rbenv install 3.2.4
- [ ] Install Ruby 3.3.1: rbenv install 3.3.1
- [ ] Fix 0 pre-existing test failures (baseline is green — good)

### Phase 1: Ruby 2.7 → 3.0 (highest risk)
**Effort:** ~2.5h · **Risk:** MED · **Blast radius:** 37 sites, 3 files · **Confidence:** HIGH
- Fix keyword argument mismatches (34 sites)
- Fix YAML.load → YAML.safe_load (3 files)
- Update .ruby-version and Gemfile ruby pin
- Run RSpec until green
- Run RuboCop until clean
- Checkpoint: /ruby-upgrade-toolkit:status → GREEN required

### Phase 2: Ruby 3.0 → 3.1
**Effort:** ~1h · **Risk:** LOW · **Confidence:** HIGH
- Update .ruby-version and Gemfile ruby pin
- Address any Psych 4 YAML changes
- Run RSpec until green, RuboCop until clean
- Checkpoint: GREEN required

### Phase 3: Ruby 3.1 → 3.2
**Effort:** ~1h · **Risk:** LOW · **Confidence:** HIGH
- Update .ruby-version and Gemfile ruby pin
- Run RSpec until green, RuboCop until clean
- Checkpoint: GREEN required

### Phase 4: Ruby 3.2 → 3.3.1
**Effort:** ~1h · **Risk:** LOW · **Confidence:** HIGH
- Update .ruby-version and Gemfile ruby pin
- Check for `it` block parameter conflicts
- Run RSpec until green, RuboCop until clean
- Checkpoint: GREEN required (upgrade complete)
```

Install each intermediate Ruby version via rbenv/rvm before starting the fix phases.

#### Step 3a — Fix Phase 1: 2.7 → 3.0

`/plan` in Step 2 created the task list. You can either let `/fix next` resolve the target from that list, or pass an explicit target. Both produce the same result; `next` is ergonomic once a plan exists.

Activate Ruby 3.0.7 first: `rbenv local 3.0.7`

```
/ruby-upgrade-toolkit:fix next
# equivalent to:
# /ruby-upgrade-toolkit:fix ruby:3.0.7
```

Claude applies changes in this order:
1. Updates `.ruby-version` to `3.0.7`, updates `Gemfile` ruby pin to `~> 3.0`
2. Runs `bundle install` — updates any gems that require it
3. Fixes all 34 keyword argument sites (reads each file, applies Pattern A or B, runs the file's tests)
4. Replaces `YAML.load` with `YAML.safe_load` in 3 files
5. Runs full RSpec suite — iterates on any failures until green
6. Runs RuboCop (`-a` then `-A`) — iterates on remaining offenses until clean
7. Runs verification (status) and, on GREEN/YELLOW, **prompts you to commit** with a detailed message:

```
━━━ Phase verification: GREEN ━━━
chore(upgrade): ruby 3.0.7 phase

Version pins:
- .ruby-version: 2.7.8 → 3.0.7
- Gemfile ruby directive: "~> 3.0"

Ruby code changes:
- Keyword argument fixes: 34 sites across 12 files
- YAML.load → YAML.safe_load: 3 occurrences

Verification:
- RSpec: 312 examples, 0 failures (0 pre-existing, 0 new)
- RuboCop: 0 offenses
- Deprecation warnings: 0
- Tier: GREEN

Commit this now? [yes / edit / no]
```

8. On `yes`, creates the commit. On `edit`, lets you revise the message first. On `no`, leaves the working tree dirty. Then produces a fix summary.

```
## Upgrade Fix Summary
Ruby: 2.7.8 → 3.0.7
Scope: full project
Commit: abc1234

### Ruby Code Changes
- Keyword argument fixes: 12 files, 34 occurrences
- YAML.load → safe_load: 3 occurrences

### RSpec
- Before: 0 failures  After: 0 failures ✓

### RuboCop
- Before: 0 offenses  After: 0 offenses ✓

### Manual Action Required
- .github/workflows/ci.yml: update ruby-version from 2.7 to 3.0
```

#### Checkpoint after Phase 1

The per-phase commit is the primary checkpoint, but `status` is still useful as a full dashboard (Zeitwerk, outdated gems, etc.):

```
/ruby-upgrade-toolkit:status
```

```
## Overall Readiness: GREEN
Ruby: 3.0.7 / Rails: not present
Tests: PASSING (312 examples, 0 failures)
Deprecation warnings: 0
RuboCop offenses: 0
```

GREEN — proceed to Phase 2.

#### Steps 3b–3d — Phases 2, 3, 4 (repeat the pattern)

Activate each intermediate Ruby, then run `/fix next` — it will resolve the target from whatever is still pending in the task list:

```
rbenv local 3.1.6
/ruby-upgrade-toolkit:fix next

rbenv local 3.2.4
/ruby-upgrade-toolkit:fix next

rbenv local 3.3.1
/ruby-upgrade-toolkit:fix next          # last apply phase — upgrade complete
```

`status` is still available any time you want a full dashboard (`/ruby-upgrade-toolkit:status`), but fix's built-in verification has already gated each commit.

Phases 2–4 are typically much faster than Phase 1. The 2.7→3.0 step carries the bulk of the breaking changes.

#### Final status — upgrade complete

```
## Overall Readiness: GREEN
Ruby: 3.3.1 / Rails: not present
Tests: PASSING (312 examples, 0 failures)
Deprecation warnings: 0
Ruby warnings: 0
RuboCop offenses: 0

Suggested Next Step: Update CI/CD ruby-version and merge your upgrade branch.
```

---

### Scenario 2: Coordinated Ruby + Rails upgrade (Ruby 2.7 → 3.3, Rails 6.1 → 8.0)

**Starting state:** Ruby 2.7.8, Rails 6.1.7, full Rails app with RSpec, PostgreSQL.

> **Tip:** This scenario can be run automatically with `/ruby-upgrade-toolkit:upgrade ruby:3.3.1 rails:8.0`. The manual walkthrough below is useful when you want to inspect each phase before proceeding.

**Key rule:** Always complete the full Ruby upgrade before starting the Rails upgrade. Ruby and Rails upgrades interact — attempting both simultaneously creates a debugging nightmare.

#### Step 1 — Audit

```
/ruby-upgrade-toolkit:audit ruby:3.3.1 rails:8.0
```

The audit covers both upgrade targets in one pass:

```
# Ruby Upgrade Audit Report
Current: Ruby 2.7.8 / Rails 6.1.7
Target:  Ruby 3.3.1 / Rails 8.0
Upgrade Path: Ruby: 2.7→3.0→3.1→3.2→3.3 | Rails: 6.1→7.0→7.1→8.0

## Critical Issues
### Keyword Argument Mismatches (Ruby 3.0)
- 41 call sites with potential mismatch

## Rails Deprecations
### Dynamic Warnings (from test suite)
- 23 unique deprecation patterns
### Static Pattern Counts
| Pattern           | Count |
|-------------------|-------|
| update_attributes | 8     |
| before_filter     | 12    |
| redirect_to :back | 3     |
| old enum syntax   | 6     |

## Gem Compatibility
### Must Update
| Gem          | Current | Required |
|--------------|---------|----------|
| devise       | 4.7     | >= 4.9   |
| sidekiq      | 5.2     | >= 6.0   |
| ransack      | 2.1     | >= 4.0   |

## Effort Estimate
Overall: High
- Ruby keyword arg fixes: ~41 sites
- Rails deprecation fixes: ~32 patterns across ~18 files
- Gem updates: 3 gems with significant version jumps
- Rails multi-step: 6.1 → 7.0 → 7.1 → 8.0 (3 Rails phases)
```

#### Step 2 — Plan

```
/ruby-upgrade-toolkit:plan ruby:3.3.1 rails:8.0
```

The plan sequences Ruby phases first, Rails phases second:

```
## Upgrade Roadmap: Ruby 2.7→3.3, Rails 6.1→8.0

### Estimate Summary
| Phase                 | Effort | Risk | Blast radius                 | Confidence |
|-----------------------|--------|------|------------------------------|------------|
| Ruby Phase 1: 2.7→3.0 | ~3h    | MED  | 41 sites, 5 files, 1 gem     | HIGH       |
| Ruby Phase 2: 3.0→3.1 | ~1h    | LOW  | 0 sites                      | HIGH       |
| Ruby Phase 3: 3.1→3.2 | ~1h    | LOW  | 0 sites                      | HIGH       |
| Ruby Phase 4: 3.2→3.3 | ~1h    | LOW  | 0 sites                      | HIGH       |
| Rails Phase 1: 6.1→7.0| ~4h    | HIGH | ~21 sites, 12 files, 2 gems  | MED        |
| Rails Phase 2: 7.0→7.1| ~2h    | MED  | ~8 sites, 4 files            | MED        |
| Rails Phase 3: 7.1→8.0| ~2.5h  | MED  | ~6 sites, 6 files, 1 gem     | MED        |
| Phase 3: Verification | ~1h    | LOW  | —                            | HIGH       |
| **Total**             | **~15.5h** | **HIGH** | ~76 sites, 27 files, 3 gems | **MED** |

Formulas:
- Ruby 2.7→3.0 = 41 kwarg × 2min + 1 gem × 30min + 1 hop × 60min = 172min ≈ 3h
- Rails 6.1→7.0 = 21 deprecations × 5min + 12 config × 10min + 2 gems × 30min + 1 hop × 60min = 345min ≈ 4h
- Rails 7.1→8.0 = 6 deprecations × 5min + 6 config × 10min + 1 gem × 30min + 1 hop × 60min = 180min ≈ 2.5h
- Risk escalated to HIGH because Rails hops > 1 and `devise` gem pin required native-ext spike

### Prerequisites
- [ ] Install Ruby 3.0.7, 3.1.6, 3.2.4, 3.3.1

### Ruby Phase 1: 2.7 → 3.0  (keyword args, YAML)
**Effort:** ~3h · **Risk:** MED · **Blast radius:** 41 sites, 5 files, 1 gem · **Confidence:** HIGH

### Ruby Phase 2: 3.0 → 3.1
### Ruby Phase 3: 3.1 → 3.2
### Ruby Phase 4: 3.2 → 3.3  ← Ruby upgrade complete here

### Rails Phase 1: 6.1 → 7.0  (enum syntax, Zeitwerk, filter→action)
**Effort:** ~4h · **Risk:** HIGH · **Blast radius:** 21 sites, 12 files, 2 gems · **Confidence:** MED

### Rails Phase 2: 7.0 → 7.1  (load_defaults, encryption)
### Rails Phase 3: 7.1 → 8.0  (config updates, gem updates)

### Final Verification
**Effort:** ~1h · **Risk:** LOW · **Confidence:** HIGH
- [ ] Full RSpec suite green
- [ ] 0 deprecation warnings
- [ ] 0 RuboCop offenses
- [ ] Update CI/CD and Dockerfiles manually
```

#### Step 3 — Ruby upgrade phases (same as Scenario 1)

Work through Phases 1–4 exactly as in Scenario 1. Activate each Ruby version before running its fix phase:

```
rbenv local 3.0.7
/ruby-upgrade-toolkit:fix ruby:3.0.7
/ruby-upgrade-toolkit:status   # must be GREEN

rbenv local 3.1.6
/ruby-upgrade-toolkit:fix ruby:3.1.6
/ruby-upgrade-toolkit:status   # must be GREEN

rbenv local 3.2.4
/ruby-upgrade-toolkit:fix ruby:3.2.4
/ruby-upgrade-toolkit:status   # must be GREEN

rbenv local 3.3.1
/ruby-upgrade-toolkit:fix ruby:3.3.1
/ruby-upgrade-toolkit:status   # must be GREEN
```

Do not start Rails phases until the final Ruby status is GREEN.

#### Step 4 — Rails Phase 1: 6.1 → 7.0

```
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:7.0
```

Claude applies:
1. Updates `gem 'rails'` pin to `~> 7.0`, runs `bundle update rails`
2. Runs `bin/rails app:update` — reviews generated diffs
3. Updates `config.load_defaults 7.0`
4. Applies safe deprecation fixes: `update_attributes→update` (8 occurrences), `before_filter→before_action` (12 occurrences), `redirect_to :back→redirect_back` (3 occurrences), `enum` syntax rewrites (6 occurrences)
5. Updates gem versions for Rails 7.0 compatibility: devise, sidekiq, ransack
6. Runs RSpec iteratively until green
7. Runs RuboCop until clean

```
/ruby-upgrade-toolkit:status
```

Expected: GREEN before proceeding.

#### Step 5 — Rails Phase 2: 7.0 → 7.1

```
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:7.1
```

```
/ruby-upgrade-toolkit:status   # GREEN required
```

#### Step 6 — Rails Phase 3: 7.1 → 8.0

```
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0
```

```
/ruby-upgrade-toolkit:status   # GREEN = upgrade complete
```

#### Final status

```
## Overall Readiness: GREEN
Ruby: 3.3.1 / Rails: 8.0.0
load_defaults: 8.0
Tests: PASSING (847 examples, 0 failures)
Deprecation warnings: 0
RuboCop offenses: 0

Suggested Next Step: Update CI/CD ruby-version and rails version, update Dockerfiles, merge.
```

---

### Scenario 3: Rails-only upgrade (Ruby unchanged, Rails 7.0 → 8.0)

**Starting state:** Ruby 3.2.4 (staying on 3.2), Rails 7.0.8. No Ruby version change needed.

> **Tip:** This scenario can be run automatically with `/ruby-upgrade-toolkit:upgrade ruby:3.2.4 rails:8.0`. Pass the current Ruby version — the upgrade command detects no Ruby change is needed and skips Ruby phases entirely.

Pass the current Ruby version in all commands — the fix skill detects that it matches the active Ruby and skips Ruby-specific changes, applying only Rails fixes.

#### Step 1 — Audit

```
/ruby-upgrade-toolkit:audit ruby:3.2.4 rails:8.0
```

Since Ruby target equals current, the audit skips Ruby breaking changes and focuses on Rails:

```
# Ruby Upgrade Audit Report
Current: Ruby 3.2.4 / Rails 7.0.8
Target:  Ruby 3.2.4 / Rails 8.0
Upgrade Path: Ruby: no change | Rails: 7.0 → 7.1 → 8.0

## Critical Issues
(none — Ruby version unchanged)

## Rails Deprecations
### Dynamic Warnings
- 18 unique deprecation patterns
### Static Pattern Counts
| Pattern           | Count |
|-------------------|-------|
| update_attributes | 5     |
| old enum syntax   | 3     |
| redirect_to :back | 1     |

## Gem Compatibility
### Must Update
| Gem       | Current | Required |
|-----------|---------|----------|
| puma      | 5.6     | >= 6.0   |
| nokogiri  | 1.13    | >= 1.15  |

## Effort Estimate
Overall: Low–Medium
- No Ruby code changes required
- Rails deprecation fixes: ~9 patterns, ~7 files
- Rails: 2 upgrade steps (7.0→7.1→8.0)
```

#### Step 2 — Plan

```
/ruby-upgrade-toolkit:plan ruby:3.2.4 rails:8.0
```

```
## Upgrade Roadmap: Rails 7.0 → 8.0 (Ruby unchanged at 3.2.4)

### Estimate Summary
| Phase                 | Effort | Risk | Blast radius              | Confidence |
|-----------------------|--------|------|---------------------------|------------|
| Rails Phase 1: 7.0→7.1| ~2h    | LOW  | 5 sites, 4 files          | HIGH       |
| Rails Phase 2: 7.1→8.0| ~2h    | MED  | 4 sites, 3 files, 1 gem   | HIGH       |
| Phase 3: Verification | ~1h    | LOW  | —                         | HIGH       |
| **Total**             | **~5h** | **MED** | 9 sites, 7 files, 1 gem | **HIGH** |

Formulas:
- Rails 7.0→7.1 = 5 deprecations × 5min + 4 config × 10min + 1 hop × 60min = 125min ≈ 2h
- Rails 7.1→8.0 = 4 deprecations × 5min + 3 config × 10min + 1 gem × 30min + 1 hop × 60min = 140min ≈ 2h

### Prerequisites
- [ ] Baseline: 0 test failures

### Rails Phase 1: 7.0 → 7.1
**Effort:** ~2h · **Risk:** LOW · **Blast radius:** 5 sites, 4 files · **Confidence:** HIGH
- Update rails gem pin
- Run bin/rails app:update, review diffs
- Set config.load_defaults 7.1
- Apply deprecation fixes
- RSpec green + RuboCop clean
- Checkpoint: status GREEN required

### Rails Phase 2: 7.1 → 8.0
**Effort:** ~2h · **Risk:** MED · **Blast radius:** 4 sites, 3 files, 1 gem · **Confidence:** HIGH
- Update rails gem pin
- Run bin/rails app:update, review diffs
- Set config.load_defaults 8.0
- Apply any remaining deprecation fixes
- RSpec green + RuboCop clean
- Checkpoint: status GREEN = done
```

#### Step 3 — Rails Phase 1: 7.0 → 7.1

```
/ruby-upgrade-toolkit:fix ruby:3.2.4 rails:7.1
```

Claude detects that Ruby target matches current and skips all Ruby-specific steps. It applies only:
1. Rails gem pin update → `bundle update rails`
2. `bin/rails app:update` diff review
3. `config.load_defaults 7.1`
4. Deprecation fixes: `update_attributes→update`, enum syntax, `redirect_to :back`
5. Gem updates: puma, nokogiri
6. Iterative RSpec until green
7. Iterative RuboCop until clean

```
/ruby-upgrade-toolkit:status
```

```
## Overall Readiness: GREEN
Ruby: 3.2.4 (unchanged) / Rails: 7.1.0
Tests: PASSING (634 examples, 0 failures)
Deprecation warnings: 0
RuboCop offenses: 0
```

#### Step 4 — Rails Phase 2: 7.1 → 8.0

```
/ruby-upgrade-toolkit:fix ruby:3.2.4 rails:8.0
/ruby-upgrade-toolkit:status
```

```
## Overall Readiness: GREEN
Ruby: 3.2.4 (unchanged) / Rails: 8.0.0
Tests: PASSING (634 examples, 0 failures)
Deprecation warnings: 0
RuboCop offenses: 0

Suggested Next Step: Update CI/CD rails version, update Dockerfiles, merge.
```

---

### Quick reference

```bash
# Full automated upgrade (recommended starting point)
/ruby-upgrade-toolkit:upgrade ruby:3.3.1
/ruby-upgrade-toolkit:upgrade ruby:3.3.1 rails:8.0

# Read-only scan before touching anything
/ruby-upgrade-toolkit:audit ruby:3.3.1 rails:8.0

# Generate a phased roadmap without executing it
/ruby-upgrade-toolkit:plan ruby:3.3.1 rails:8.0

# Apply fixes for a specific phase manually
/ruby-upgrade-toolkit:fix ruby:3.3.1
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0

# Fix deprecations in a single file (gem/pin changes still apply project-wide)
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/models/order.rb

# Fix an entire directory
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/controllers/

# Check upgrade health at any point without making changes
/ruby-upgrade-toolkit:status
```

## Agents

Two agents activate automatically based on natural language context — no slash commands needed.

### upgrade-auditor

Fires when you describe an upgrade intent:
- "I need to upgrade this app from Rails 7 to 8"
- "What would it take to get to Ruby 3.3?"
- "How bad is our deprecation situation?"

Detects whether the project is Rails or plain Ruby automatically. Produces the same findings report as `/ruby-upgrade-toolkit:audit` and ends with the recommended command sequence.

### deprecation-fixer

Fires when you ask to fix deprecations in a specific file or directory:
- "Fix the deprecation warnings in app/models/user.rb"
- "Clear all deprecations from app/controllers/"

Reads each file, applies safe mechanical fixes automatically, presents complex fixes for confirmation, and runs the file's tests to verify.

## Hooks

Three automatic hooks activate when the plugin is installed:

| Hook | Event | Behavior |
|------|-------|----------|
| `block-vendor` | PreToolUse (Write/Edit) | Blocks any write to `vendor/` — use `bundle update` instead |
| `ruby-version-sync` | PostToolUse (Write/Edit) | Warns when `.ruby-version` and `Gemfile` ruby directive have different minor versions |
| `rubocop-fix` | PostToolUse (Write/Edit) | **Opt-in** — auto-corrects Style/Layout cops on edited `.rb` files |

### Enable RuboCop auto-fix

```bash
touch .ruby-upgrade-toolkit-rubocop   # enable
rm .ruby-upgrade-toolkit-rubocop      # disable
```

Requires `rubocop` in your Gemfile. Only corrects Style and Layout cops — does not touch Metrics or Lint.

## Prerequisites

- Claude Code 1.x+
- Ruby project using Bundler
- `jq` installed (required by hook scripts): `brew install jq` / `apt install jq`
- RuboCop in Gemfile (for rubocop-fix hook and `fix` command RuboCop step)
- Target Ruby version installed via rbenv or rvm before running `fix`

## Ruby ↔ Rails Version Compatibility

| Target Ruby | Minimum Rails | Recommended Rails |
|-------------|--------------|-------------------|
| 2.7         | 5.2          | 6.0–6.1           |
| 3.0         | 6.1          | 7.0               |
| 3.1         | 7.0          | 7.0–7.1           |
| 3.2         | 7.0.4        | 7.1               |
| 3.3         | 7.1          | 7.1–7.2           |
| 3.4         | 7.2          | 7.2–8.0           |

Always complete the Ruby upgrade before starting the Rails upgrade when doing both.

## CI Template

A GitHub Actions workflow template is included at `.github/workflows/ruby-upgrade-ci.yml`. Copy it to your application's `.github/workflows/` directory.

It provides three jobs:

| Job | When it runs | What it checks |
|-----|-------------|----------------|
| `test` | Always | Ruby deprecation warnings + RSpec/rake test |
| `rails-test` | Rails projects only (`config/application.rb` present) | DB setup, Zeitwerk, Rails deprecation count, RSpec |
| `migration-safety` | When `db/migrate/` exists | Risky migration pattern counts |

Adjust the `ruby-version` matrix to the versions relevant to your upgrade path.

## Contributing

Issues and PRs welcome at [github.com/dhruvasagar/ruby-upgrade-toolkit](https://github.com/dhruvasagar/ruby-upgrade-toolkit).

### Adding a new Rails version guide

Add a file at `skills/rails-upgrade-guide/references/rails-X-to-Y.md` and reference it in `skills/rails-upgrade-guide/SKILL.md`.

### Updating the gem compatibility matrix

Edit `skills/rails-upgrade-guide/references/compatibility-matrix.md`. Follow the existing table format.

### Adding a new Ruby version's breaking changes

Add breaking change patterns to the relevant step in `skills/audit/SKILL.md` (Step 3) and `skills/fix/SKILL.md` (Step 4), scoped to the relevant version pair.

## License

MIT
