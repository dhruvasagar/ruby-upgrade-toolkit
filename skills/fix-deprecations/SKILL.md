---
name: Fix Deprecations
description: Use when the user runs /fix-deprecations or asks to fix Rails deprecation warnings, apply deprecation fixes, update deprecated code patterns, or resolve a specific DEPRECATION WARNING. Can target a single file or the whole app. Applies safe automated fixes and guides manual fixes for complex cases.
argument-hint: "<file_or_directory> (e.g. app/models/user.rb or app/controllers/)"
allowed-tools: Read, Edit, Bash, Grep, Glob
version: 0.1.0
---

# Fix Deprecations

Fix Rails deprecation warnings systematically: safe patterns are applied automatically, complex patterns require guided review.

## Step 1: Scope the Work

If a specific file was passed, focus on that file. Otherwise, find the highest-priority files:

```bash
# Files with the most deprecation hits
RAILS_ENV=test bundle exec rspec --no-color 2>&1 | grep "DEPRECATION" | grep -oP "(?<=from ).+?(?=:\d)" | sort | uniq -c | sort -rn | head -20
# or
RAILS_ENV=test bundle exec rails test 2>&1 | grep "DEPRECATION" | grep -oP "(?<=called from ).+?(?=:\d)" | sort | uniq -c | sort -rn | head -20
```

Read the target file(s) before making any changes.

## Step 2: Identify the Rails Version

```bash
bundle exec rails -v
```

Load the relevant patterns from `$CLAUDE_PLUGIN_ROOT/skills/fix-deprecations/references/fix-patterns.md` for the current Rails version.

## Step 3: Apply Safe Automated Fixes

These patterns are mechanical and safe to apply automatically (no semantic change):

### `update_attributes` → `update`
```ruby
# Before
user.update_attributes(name: "Alice")

# After
user.update(name: "Alice")
```
Search: `grep -rn "\.update_attributes(" [scope]`

### `before_filter` / `after_filter` / `around_filter` → `_action`
```ruby
# Before
before_filter :authenticate_user!
after_filter :log_action

# After
before_action :authenticate_user!
after_action :log_action
```
Search: `grep -rn "before_filter\|after_filter\|around_filter" [scope]`

### `redirect_to :back` → `redirect_back`
```ruby
# Before
redirect_to :back

# After
redirect_back(fallback_location: root_path)
```
Search: `grep -rn "redirect_to :back" [scope]`

### `require_dependency` → remove (Rails 7+)
```ruby
# Before
require_dependency 'some/module'

# After (remove the line entirely — Zeitwerk handles it)
```
Search: `grep -rn "require_dependency" [scope]`

### Old enum syntax (Rails 8)
```ruby
# Before
enum status: [:draft, :published, :archived]
enum status: { draft: 0, published: 1 }

# After
enum :status, [:draft, :published, :archived]
enum :status, { draft: 0, published: 1 }
```
Search: `grep -rn "^ *enum [a-z_]*:" [scope]`

### `success?` → `successful?` on responses (Rails 7.1)
```ruby
# Before
response.success?
# After
response.successful?
```

## Step 4: Guided Fixes for Complex Patterns

These require understanding context before applying:

### Open redirect (Rails 7)
When `redirect_to` uses user-controlled input:

```ruby
# BEFORE (raises RedirectBackError in Rails 7)
redirect_to params[:return_to]

# AFTER option A — safe: only redirect to known paths
redirect_to params[:return_to].presence || root_path

# AFTER option B — explicit allow for external (if intentional)
redirect_to params[:return_to], allow_other_host: true
```

For each occurrence, read the surrounding code and determine whether the redirect target is user-controlled. If uncertain, use option A.

### `has_and_belongs_to_many` migration

This cannot be auto-fixed — it requires a migration and code changes. Present the user with:

1. Current HABTM association
2. The join table name
3. The 3-step migration plan (add join model, migration, update associations)
4. Ask: "Apply this migration? [y/N]"

### `protected_attributes` / `attr_accessible`

If the app uses these, it's on Rails < 4. Build a full Strong Parameters conversion plan, file by file.

### Custom `respond_to_missing?` patterns

Show the deprecated vs. correct signature and ask before editing.

## Step 5: Verify Each Fix

After applying fixes to a file:

```bash
# Run just the file's tests
bundle exec rspec spec/path/matching/file_spec.rb
# or
bundle exec rails test test/path/matching/file_test.rb
```

If tests pass, proceed to the next file.

## Step 6: Final Verification

After all fixes in scope:

```bash
# Confirm deprecation warnings are gone
RAILS_ENV=test bundle exec rspec 2>&1 | grep -c "DEPRECATION" || echo "0 deprecation warnings"
```

## Output Format

For each file modified, summarize:
```
app/models/user.rb
  - Fixed 3x update_attributes → update
  - Fixed 1x enum syntax
  Tests: PASSED
```

At the end:
```
Fixed [N] deprecations across [M] files.
Remaining: [K] warnings (complex — require manual review)
```
