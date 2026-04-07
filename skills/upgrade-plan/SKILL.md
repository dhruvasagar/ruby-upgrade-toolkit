---
name: Upgrade Plan
description: Use when the user runs /upgrade-plan or asks to create an upgrade plan, generate a Rails migration roadmap, or plan a Rails version bump. Accepts source and target versions (e.g. "6.1 to 7.1"). Produces a phased, actionable upgrade plan with checklists tailored to the specific app.
argument-hint: "<source_version> <target_version> (e.g. 6.1 7.1)"
allowed-tools: Read, Bash, Glob, Grep
version: 0.1.0
---

# Upgrade Plan

Generate a comprehensive, phased Rails upgrade plan for this specific application.

## Step 1: Discover Current State

```bash
# Rails version
bundle exec rails -v 2>/dev/null || grep "^    rails " Gemfile.lock | head -1

# Ruby version
ruby -v

# Gemfile rails pin
grep "gem ['\"]rails['\"]" Gemfile

# Test suite health (quick check)
bundle exec rails runner "puts 'Rails loads OK'" 2>&1 | tail -5
```

Read `Gemfile`, `Gemfile.lock`, and `config/application.rb` to understand:
- Current Rails and Ruby versions
- Framework defaults currently loaded (`config.load_defaults`)
- Any non-standard configuration

## Step 2: Determine Upgrade Path

If upgrading more than one minor version (e.g. 6.0 → 8.0), create an intermediate plan:
- 6.0 → 6.1 → 7.0 → 7.1 → 8.0
- Each step must have a green test suite before the next begins

Load the relevant version guide from `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/`.

## Step 3: Scan for Known Problem Areas

```bash
# Deprecation warnings in tests
RAILS_ENV=test bundle exec rails test 2>&1 | grep -i deprecat | sort -u | head -30
# or for RSpec:
RAILS_ENV=test bundle exec rspec 2>&1 | grep -i deprecat | sort -u | head -30

# Zeitwerk check (Rails 6+)
bundle exec rails zeitwerk:check 2>/dev/null

# Outdated gems with Rails compatibility concern
bundle outdated 2>/dev/null | head -40
```

Grep for high-risk patterns based on target version:
```bash
# Rails 7 open-redirect risk
grep -rn "redirect_to.*params\|redirect_to.*request\|redirect_to.*session" app/controllers/ 2>/dev/null

# Rails 8 enum syntax
grep -rn "enum [a-z_]*:" app/models/ 2>/dev/null

# HABTM (deprecated pattern)
grep -rn "has_and_belongs_to_many" app/models/ 2>/dev/null
```

## Step 4: Generate the Plan

Produce a Markdown-formatted upgrade plan with these sections:

### Header
```
# Rails [SOURCE] → [TARGET] Upgrade Plan
Generated: [date]
App: [app name from config/application.rb]
```

### Phase 0: Prerequisites
- [ ] Ruby version requirement met (list minimum)
- [ ] All current tests passing (`bundle exec rspec` or `rails test`)
- [ ] Git branch created: `git checkout -b rails-upgrade-[TARGET]`
- [ ] CI pipeline configured for the upgrade branch

### Phase 1: Gem Dependency Preparation
- List each gem that needs updating with required version
- Flag any gems with no known compatible release (need investigation)
- Provide `bundle update` strategy (conservative: update one-by-one vs. bulk)

### Phase 2: Rails Update
- Update Gemfile pin
- Run `bundle update rails`
- Run `bin/rails app:update` (review each diff)
- Set `config.load_defaults [TARGET]` — **keep new defaults disabled initially**
- Copy `config/initializers/new_framework_defaults_X_Y.rb` stub

### Phase 3: Breaking Changes (version-specific)
List every breaking change from the version guide that applies to THIS app (skip irrelevant ones).
For each item:
- What to search for
- What to change
- Test to verify

### Phase 4: Deprecation Fixes
- Run deprecation audit (use `/deprecation-audit`)
- Fix each deprecation category
- Re-run until warnings are zero

### Phase 5: New Framework Defaults
Enable each new default one at a time:
- Enable default → run tests → fix failures → commit → repeat

### Phase 6: Verification
- [ ] Full test suite green
- [ ] No remaining deprecation warnings
- [ ] Staging deploy and smoke test
- [ ] Performance benchmarks unchanged

### Estimated Risk Summary
Rate overall complexity: Low / Medium / High
Flag top 3 risks with mitigation notes.

## Output Format

Write the plan to a file if the user has a specific location preference; otherwise print it directly. Include a `## Quick Commands` section at the end with copy-paste bash commands for each phase.
