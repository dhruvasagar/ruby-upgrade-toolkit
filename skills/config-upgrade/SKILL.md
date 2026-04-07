---
name: Config Upgrade
description: Use when the user runs /config-upgrade or asks to update Rails configuration, migrate framework defaults, update config/application.rb for a new Rails version, or apply new Rails default settings. Reviews config files and applies version-appropriate changes.
argument-hint: "<target_rails_version> (e.g. 7.1 or 8.0)"
allowed-tools: Read, Edit, Bash, Grep, Glob
version: 0.1.0
---

# Config Upgrade

Update Rails configuration files to match the target version's conventions and enable new framework defaults safely.

## Step 1: Inventory Configuration Files

Read each file before making changes:

```bash
# Core config files
ls config/application.rb config/environment.rb
ls config/environments/
ls config/initializers/ | head -30

# Check current load_defaults setting
grep -n "load_defaults\|config\.load_defaults" config/application.rb
```

Read `config/application.rb`, `config/environments/development.rb`, `config/environments/production.rb`, and `config/environments/test.rb`.

## Step 2: Run `bin/rails app:update`

This is the canonical tool — it generates diffs for all config files:

```bash
# Run interactively-safe version (answers 'd' to show diff, not apply)
# Claude should review the output and apply changes selectively
THOR_MERGE=cat bundle exec rails app:update 2>&1
```

Review each generated diff. Apply changes that:
- Add new configuration options
- Update deprecated option names
- Remove configuration options that no longer exist

Do NOT blindly accept all diffs — some override intentional customizations.

## Step 3: Update `load_defaults`

The safest path is to update `load_defaults` to the new version **while keeping the `new_framework_defaults` initializer** to selectively re-enable old behaviors:

```ruby
# config/application.rb
# Change this:
config.load_defaults 7.0
# To this:
config.load_defaults 8.0
```

Then create a `config/initializers/new_framework_defaults_8_0.rb` stub to re-enable any new defaults that break the app, disabling them one at a time as fixes are applied.

## Step 4: Apply Version-Specific Config Changes

### Rails 6 config changes

```ruby
# config/application.rb additions
config.action_mailer.delivery_job = "ActionMailer::MailDeliveryJob"
config.active_record.collection_cache_versioning = true

# config/initializers/ — run the new defaults generator
bin/rails generate rails:update
```

### Rails 7 config changes

```ruby
# config/application.rb
# Open redirect protection — new default, may need explicit opt-out per controller
config.action_controller.raise_on_open_redirects = true

# config/environments/production.rb
# If using force_ssl:
# OLD: config.force_ssl = true
# NEW: config.assume_ssl = true (if behind load balancer terminating SSL)
#   or: config.force_ssl = true (if Rails handles SSL directly)
```

### Rails 8 config changes

```ruby
# config/application.rb
# New association inversion — may affect eager loading
# config.active_record.automatically_invert_plural_associations = false  # opt out if breaking

# config/environments/
# Remove any options that no longer exist (Rails will warn at boot)
```

## Step 5: Audit `config/initializers/`

Read each initializer and flag:
- Initializers that re-implement behavior now built into Rails
- Initializers referencing removed constants or APIs
- Initializers setting options that no longer exist

Common cleanup:
```bash
# Find initializers referencing deprecated APIs
grep -rn "ActionDispatch::ParamsParser\|ActionDispatch::Head\|Rack::Lock\|Rack::Cache" config/initializers/
grep -rn "config\.whiny_nils\|config\.dependency_loading" config/initializers/ config/application.rb
```

## Step 6: Verify Boot

```bash
# App boots cleanly
bundle exec rails runner "puts Rails.version" 2>&1

# No config-related warnings at boot
bundle exec rails runner "puts 'OK'" 2>&1 | grep -v "^OK"

# Test suite still passes
bundle exec rspec --no-color 2>&1 | tail -5
```

## Step 7: Report

Summarize changes made:
```
## Config Upgrade Report
Target: Rails [version]

### Files Modified
- config/application.rb: updated load_defaults, removed [N] deprecated options
- config/environments/production.rb: updated force_ssl setting
- config/initializers/cors.rb: updated for new Rack version

### Deprecated Options Removed
[list]

### New Defaults Enabled
[list]

### New Defaults Deferred (need investigation)
[list — these are in new_framework_defaults_X_Y.rb]

### Manual Review Needed
[list of initializers/options that need human decision]
```
