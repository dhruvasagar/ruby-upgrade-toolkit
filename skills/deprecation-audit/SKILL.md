---
name: Deprecation Audit
description: Use when the user runs /deprecation-audit or asks to find deprecation warnings, scan for Rails deprecations, check what's deprecated in the app, or audit deprecation issues before an upgrade. Captures warnings from the test suite and static patterns from the codebase.
argument-hint: "[path] (optional: scope to a file or directory)"
allowed-tools: Bash, Read, Grep, Glob
version: 0.1.0
---

# Deprecation Audit

Perform a comprehensive deprecation audit combining dynamic (test suite) and static (grep) analysis.

## Step 1: Dynamic Capture — Run the Test Suite

Capture all deprecation warnings emitted during test execution. Use the script at `$CLAUDE_PLUGIN_ROOT/skills/deprecation-audit/scripts/capture-deprecations.sh`:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/deprecation-audit/scripts/capture-deprecations.sh"
```

Or manually:

```bash
# RSpec
RAILS_ENV=test bundle exec rspec 2>&1 | grep -E "DEPRECATION|deprecated" | sort | uniq -c | sort -rn > /tmp/deprecations.txt
cat /tmp/deprecations.txt

# Minitest
RAILS_ENV=test bundle exec rails test 2>&1 | grep -E "DEPRECATION|deprecated" | sort | uniq -c | sort -rn > /tmp/deprecations.txt
cat /tmp/deprecations.txt

# Rails runner (catches autoload/initializer deprecations)
RAILS_ENV=development bundle exec rails runner "puts 'loaded'" 2>&1 | grep -E "DEPRECATION|deprecated"
```

## Step 2: Static Analysis — Pattern Search

Search for known deprecated patterns in the codebase. The specific patterns depend on the current and target Rails version — load the `rails-upgrade-guide` skill to identify which patterns apply.

### Universal deprecated patterns (all versions)

```bash
# update_attributes (removed in Rails 6)
grep -rn "\.update_attributes(" app/ --include="*.rb"

# has_and_belongs_to_many
grep -rn "has_and_belongs_to_many" app/models/ --include="*.rb"

# require_dependency (removed in Rails 7)
grep -rn "require_dependency" app/ --include="*.rb" lib/ --include="*.rb"

# before_filter / after_filter / around_filter (removed in Rails 5.1)
grep -rn "before_filter\|after_filter\|around_filter" app/ --include="*.rb"

# redirect_to :back (removed in Rails 5.1)
grep -rn "redirect_to :back" app/ --include="*.rb"

# find_by_* dynamic finders (removed in Rails 4.0, but still encountered)
grep -rn "find_by_[a-z_]*(" app/ --include="*.rb"
```

### Rails 6 → 7 specific

```bash
# Open redirect risk (new enforcement in Rails 7)
grep -rn "redirect_to.*params\[" app/controllers/ --include="*.rb"
grep -rn "redirect_to.*params\." app/controllers/ --include="*.rb"

# form_with local: false (default changed)
grep -rn "form_with.*local: false" app/views/ --include="*.erb" --include="*.haml"

# ActionController::Parameters with non-permitted keys
grep -rn "params\[:" app/controllers/ --include="*.rb" | head -20
```

### Rails 7 → 8 specific

```bash
# Old enum syntax
grep -rn "enum [a-z_]*:" app/models/ --include="*.rb"

# ActiveRecord::Base.logger
grep -rn "ActiveRecord::Base\.logger" app/ --include="*.rb" config/ --include="*.rb"

# Sprockets directives (if migrating to Propshaft)
grep -rn "^//= require\|^//= require_tree\|^//= require_self" app/assets/ 2>/dev/null
```

## Step 3: Zeitwerk Check (Rails 6+)

```bash
bundle exec rails zeitwerk:check 2>&1
```

Any `expected file ... to define constant ...` error is a naming mismatch that must be fixed.

## Step 4: Report Results

Present results in this format:

```
## Deprecation Audit Report
Date: [date]
Rails version: [current]

### Dynamic Warnings ([N] unique warnings)
[Group by warning type, show count and example location]

### Static Pattern Matches
| Pattern | Count | Files |
|---------|-------|-------|
| update_attributes | 3 | app/models/user.rb, ... |
...

### Zeitwerk Issues
[List any constant naming mismatches]

### Priority Order
1. CRITICAL (will break after upgrade): [list]
2. HIGH (emitting warnings, must fix before upgrade): [list]
3. MEDIUM (deprecated but still working): [list]
4. LOW (style/best-practice): [list]
```

## Step 5: Recommended Next Steps

After the report, suggest:
- Run `/fix-deprecations` on the highest-priority files
- Run `/gem-compatibility-check` to find gem-level deprecations
- Commit a baseline before making fixes so diffs are clean
