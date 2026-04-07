---
name: Upgrade Status
description: Use when the user runs /upgrade-status or asks for the current upgrade status, Rails upgrade progress report, or a summary of what's done and what's remaining in the upgrade. Produces a comprehensive health report.
argument-hint: "[target_version] (optional)"
allowed-tools: Bash, Read, Grep, Glob
version: 0.1.0
---

# Upgrade Status

Generate a comprehensive Rails upgrade health report showing current state, progress, and remaining work.

## Step 1: Gather Current State

```bash
# Rails and Ruby versions
bundle exec rails -v 2>/dev/null
ruby -v

# load_defaults setting
grep "load_defaults" config/application.rb

# Git branch context
git branch --show-current 2>/dev/null
git log --oneline -5 2>/dev/null
```

## Step 2: Test Suite Health

```bash
# Run test suite and capture summary
if [[ -f ".rspec" ]] || [[ -d "spec" ]]; then
  bundle exec rspec --no-color --format progress 2>&1 | tail -10
else
  bundle exec rails test 2>&1 | tail -10
fi
```

## Step 3: Deprecation Warning Count

```bash
# Count remaining deprecation warnings
if [[ -f ".rspec" ]] || [[ -d "spec" ]]; then
  DEPR=$(RAILS_ENV=test bundle exec rspec --no-color 2>&1 | grep -c "DEPRECATION" || echo 0)
else
  DEPR=$(RAILS_ENV=test bundle exec rails test 2>&1 | grep -c "DEPRECATION" || echo 0)
fi
echo "Deprecation warnings: $DEPR"
```

## Step 4: Gem Compatibility Status

```bash
# Gems that are outdated vs. latest
bundle outdated 2>/dev/null | grep -E "^  \*" | head -20
```

Check `Gemfile.lock` for gems known to be incompatible with the target Rails version (cross-reference the compatibility matrix).

## Step 5: Known Risky Pattern Count

Quick grep for high-priority patterns (not an exhaustive audit — just a health signal):

```bash
echo "=== Pattern Counts ==="
echo "update_attributes: $(grep -rn '\.update_attributes(' app/ --include='*.rb' 2>/dev/null | wc -l)"
echo "before_filter: $(grep -rn 'before_filter\|after_filter\|around_filter' app/ --include='*.rb' 2>/dev/null | wc -l)"
echo "redirect_to :back: $(grep -rn 'redirect_to :back' app/ --include='*.rb' 2>/dev/null | wc -l)"
echo "require_dependency: $(grep -rn 'require_dependency' app/ lib/ --include='*.rb' 2>/dev/null | wc -l)"
echo "HABTM: $(grep -rn 'has_and_belongs_to_many' app/ --include='*.rb' 2>/dev/null | wc -l)"
echo "Old enum syntax: $(grep -rn '^ *enum [a-z_]*:' app/ --include='*.rb' 2>/dev/null | wc -l)"
echo "Open redirect risk: $(grep -rn 'redirect_to.*params\[' app/controllers/ --include='*.rb' 2>/dev/null | wc -l)"
```

## Step 6: Migration Safety Status

```bash
# Count migrations not yet run
bundle exec rails db:migrate:status 2>/dev/null | grep "^  down" | wc -l

# Any new migrations since last deploy (rough check)
git diff --name-only HEAD~5..HEAD 2>/dev/null -- db/migrate/ | wc -l
```

## Step 7: Zeitwerk Check (Rails 6+)

```bash
bundle exec rails zeitwerk:check 2>&1 | grep -E "error|OK|expected"
```

## Step 8: Render the Report

Format as:

```
# Rails Upgrade Status Report
Generated: [datetime]
Branch: [branch name]

## Versions
- Ruby: [version]
- Rails (current): [version]
- Rails (target): [version or "not set"]
- load_defaults: [value in application.rb]

## Test Suite
- Status: [PASSING / FAILING]
- [N] examples, [F] failures, [P] pending

## Deprecation Warnings
- [N] warnings remaining
- [Status emoji] Target: 0 warnings before upgrading

## Remaining Deprecation Patterns
| Pattern | Count | Command to Fix |
|---------|-------|----------------|
| update_attributes | N | /fix-deprecations app/ |
| ... | | |

## Gem Compatibility
- [N] gems need updating for target Rails
- [N] gems need investigation
- Top outdated: [list top 3]

## Migration Safety
- [N] pending migrations
- [N] migrations flagged as risky (run /migration-safety-check)

## Zeitwerk
- [OK / N errors found]

## Overall Upgrade Readiness
[RED / YELLOW / GREEN]

RED: Test failures or > 20 deprecation warnings
YELLOW: 1-20 deprecation warnings or gems need updating  
GREEN: Tests passing, 0 deprecations, gems compatible

## Suggested Next Steps
1. [Highest priority action]
2. [Second priority]
3. [Third priority]
```

Keep the report concise — it should fit on one screen. Link to the relevant slash commands for each remaining task.
