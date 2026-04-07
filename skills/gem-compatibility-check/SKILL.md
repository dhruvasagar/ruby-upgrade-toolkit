---
name: Gem Compatibility Check
description: Use when the user runs /gem-compatibility-check or asks to check gem compatibility, find gems that don't support the target Rails version, identify which gems need upgrading, or audit dependencies before a Rails upgrade.
argument-hint: "<target_rails_version> (e.g. 7.1 or 8.0)"
allowed-tools: Bash, Read, Grep
version: 0.1.0
---

# Gem Compatibility Check

Audit all gems in `Gemfile.lock` for compatibility with the target Rails version, combining live RubyGems data with a curated local compatibility matrix.

## Step 1: Extract Current Gem Versions

```bash
# All gems with current versions
cat Gemfile.lock | grep -E "^    [a-z]" | sed 's/^ *//' | sort > /tmp/current-gems.txt
cat /tmp/current-gems.txt | head -30

# Rails-adjacent gems (highest risk)
grep -E "rails|active|action|sprockets|devise|pundit|kaminari|sidekiq|carrierwave|paperclip|delayed|rspec-rails|factory_bot|shoulda|capybara|webpacker|importmap|propshaft|turbo|stimulus" /tmp/current-gems.txt
```

## Step 2: Check Live Compatibility via RubyGems API

For each high-risk gem, query RubyGems for the latest version that supports the target Rails:

```bash
# Get latest version info for a gem
query_gem() {
  local gem_name="$1"
  curl -s "https://rubygems.org/api/v1/gems/${gem_name}.json" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'), d.get('homepage_uri',''))" 2>/dev/null || echo "N/A"
}

# Example: check devise
query_gem devise
```

Check the gem's GitHub releases/CHANGELOG for Rails version support notes when the API doesn't include that detail.

## Step 3: Apply the Compatibility Matrix

Cross-reference against the curated matrix at `$CLAUDE_PLUGIN_ROOT/skills/gem-compatibility-check/references/compatibility-matrix.md`.

For gems in the matrix, report the minimum required version for the target Rails. For gems not in the matrix, flag them as "needs investigation" and recommend checking their GitHub README.

## Step 4: Identify Gem Categories

Group gems into:

### Category A: Compatible as-is
Gems already meeting the minimum version requirement for the target Rails.

### Category B: Needs version bump (compatible version exists)
List: `gem_name current_version → required_version`

### Category C: Unknown — needs investigation
Gems not in the compatibility matrix. Steps to investigate:
1. Check the gem's README for Rails version badge
2. Check `CHANGELOG.md` for "Rails X.Y support" entries
3. Search GitHub issues for `rails X.Y` or `compatibility`
4. Try `bundle update gem_name` and run tests

### Category D: Incompatible / abandoned
Gems with no known compatible release:
- **paperclip** → migrate to Active Storage
- **protected_attributes** → use Strong Parameters
- **attr_accessible** → use Strong Parameters
- Any gem with last release > 3 years ago and no Rails support statement

## Step 5: bundle update Dry Run

```bash
# Check what would change without actually changing it
bundle update --dry-run rails 2>&1 | head -50

# Or update only the gems in Category B (conservative strategy)
# bundle update gem1 gem2 gem3
```

## Step 6: Report

```
## Gem Compatibility Report
Target Rails: [version]
Total gems: [N]

### Must Update Before Upgrade
| Gem | Current | Required | Action |
|-----|---------|----------|--------|
| devise | 4.7.0 | >= 4.9.3 | bundle update devise |
| ...   |        |          |        |

### Needs Investigation
- gem_name (version X.Y.Z) — no compatibility data available

### Incompatible / Abandoned
- paperclip 6.0.0 — INCOMPATIBLE with Rails 6+, migrate to Active Storage

### Compatible as-is
[N] gems require no changes

### Recommended Update Command
bundle update rails [list of gems to update together]
```

## Important Notes

- Update gems conservatively: update Rails + minimum required gems first, then iterate
- Don't bulk-update all gems simultaneously — changes become hard to bisect if tests fail
- Lock critical gems to known-good versions during the upgrade, update them after
- For gems with no active maintainer, evaluate replacing with a maintained alternative
