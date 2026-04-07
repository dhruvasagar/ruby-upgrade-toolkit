---
name: Rails Upgrade Guide
description: Consult this skill when a user is upgrading Rails, asks about breaking changes between Rails versions, needs a checklist for any version bump (5→6, 6→7, 7→8, or patch releases), or wants to understand what changed and why.
version: 0.1.0
---

# Rails Upgrade Guide

This skill provides structured, version-specific guidance for Rails upgrades. Use it to inform planning, auditing, and fixing tasks throughout the upgrade workflow.

## How to Use This Skill

1. Identify source and target Rails versions from the project's `Gemfile` or `Gemfile.lock`.
2. Load the relevant version guide from `references/` for the specific version pair.
3. Cross-reference the guide against the current codebase state.
4. Surface breaking changes relevant to the project's actual code (not every change applies to every app).

## Determining Current and Target Versions

```bash
# Current version
bundle exec rails -v

# Or from Gemfile.lock
grep "^    rails " Gemfile.lock

# Gemfile target
grep "gem 'rails'" Gemfile
```

## Version Guides

Load the appropriate reference file for the upgrade path:

- **Rails 5 → 6**: See `references/rails-5-to-6.md`
- **Rails 6 → 7**: See `references/rails-6-to-7.md`
- **Rails 7 → 8**: See `references/rails-7-to-8.md`
- **Patch releases** (e.g. 7.0 → 7.1): Focus on the CHANGELOG entries in the target version; use the minor version guide as context.

## Multi-Step Upgrades

When upgrading across multiple major versions (e.g. Rails 5 → 8), upgrade **one major version at a time**:

1. 5.2 → 6.1 (with full test suite passing)
2. 6.1 → 7.1 (with full test suite passing)
3. 7.1 → 8.0 (with full test suite passing)

Never skip versions. Each step must have a green test suite before proceeding.

## Universal Checklist (applies to every upgrade)

- [ ] Pin `gem 'rails', '~> X.Y'` in Gemfile, run `bundle update rails`
- [ ] Run `bin/rails app:update` and review each generated diff
- [ ] Set `config.load_defaults X.Y` in `application.rb`
- [ ] Address all deprecation warnings (`RAILS_ENV=test bundle exec rails test 2>&1 | grep DEPRECATION`)
- [ ] Update gem dependencies for new Rails version
- [ ] Run full test suite — achieve green before merging
- [ ] Review `config/initializers/` for anything overriding defaults that are now built-in
- [ ] Check `config/environments/` for deprecated options

## New Framework Defaults Strategy

Each Rails version ships new framework defaults behind a feature flag. The safe upgrade path:

1. Upgrade the Rails gem first (without enabling new defaults).
2. Fix all deprecations and breaking changes with old defaults active.
3. Enable new defaults **one at a time** (`config/initializers/new_framework_defaults_X_Y.rb`).
4. Run tests after each default change.
5. Remove the initializer file once all defaults are inline in `application.rb`.
