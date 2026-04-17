---
name: Upgrade Plan
description: Use when the user runs /ruby-upgrade-toolkit:plan or asks to plan a Ruby or Rails upgrade, generate an upgrade roadmap, or understand what phases are involved in bumping versions. Accepts ruby:X.Y.Z and optional rails:X.Y arguments. Produces a phased, project-specific upgrade plan with checklists.
argument-hint: "ruby:X.Y.Z [rails:X.Y]"
allowed-tools: Read, Bash, Glob, Grep
version: 0.3.0
---

# Upgrade Plan

Generate a comprehensive, phased upgrade plan tailored to this specific project.

## Argument Parsing

Extract target versions from the arguments:
- `ruby:X.Y.Z` — required target Ruby version
- `rails:X.Y` — optional target Rails version (omit if Ruby-only upgrade)

## Step 1: Detect Current Versions

```bash
# Ruby version
ruby -v 2>/dev/null || true
cat .ruby-version 2>/dev/null
grep "^ruby " Gemfile 2>/dev/null
grep -A2 "RUBY VERSION" Gemfile.lock 2>/dev/null

# Rails version (if present)
bundle exec rails -v 2>/dev/null || true
grep "gem ['\"]rails['\"]" Gemfile 2>/dev/null
grep "^    rails " Gemfile.lock 2>/dev/null | head -1
```

Read `Gemfile` and `Gemfile.lock` to understand current gem versions.
Check for `.ruby-version`, `Gemfile`, `Gemfile.lock`, and `config/application.rb`.

## Step 2: Validate Ruby ↔ Rails Compatibility

If a `rails:` argument was given, load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/ruby-rails-compatibility.md` and apply its validation rules. If the combination is incompatible, surface the reference's error template and stop before generating the plan.

## Step 3: Identify Upgrade Path

Load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/upgrade-paths.md` and use it to compute the ordered list of intermediate versions for Ruby, then Rails (if given). Each intermediate step becomes its own phase in the plan.

## Step 4: Scan for Known Problem Areas

For the test-suite baseline and the outdated-gems signal, use the canonical commands in `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/verification-suite.md` (sections "Test suite — full run" and "Outdated gems signal").

For Ruby 2.7 → 3.0 upgrades, scan for keyword argument issues:
```bash
grep -rn "def .*\*\*[a-z_]*\b" app/ lib/ --include="*.rb" 2>/dev/null | wc -l
RUBYOPT="-W:deprecated" bundle exec ruby -e "puts 'ok'" 2>&1 | head -5
```

For Rails upgrades, load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/SKILL.md` and its relevant version reference file to identify breaking changes that apply.

## Step 5: Compute Estimates

Estimates are derived from the counts collected in Step 4 — never invent numbers. If a count can't be obtained, record it as `unknown` and downgrade confidence.

### Effort (minutes → rolled up to hours)

Apply this rubric to the grep/scan results:

| Signal | Minutes each |
|--------|--------------|
| Keyword-argument call site (`def .*\*\*`) | 2 |
| `YAML.load` occurrence | 2 |
| Deprecated API match (per pattern from rails-upgrade-guide) | 5 |
| Framework default to toggle | 15 |
| `rails app:update` config diff file | 10 |
| Gem minor/patch bump | 10 |
| Gem major-version bump | 30 |
| Gem with native extension **and** no target-compatible version published | 120 |
| Each intermediate Ruby or Rails hop | +60 (overhead per hop) |

Round each phase total up to the nearest half-hour. Always show the formula (`12 × 2min + 3 × 30min = 114min ≈ 2h`) so the user can sanity-check.

### Risk (LOW / MED / HIGH)

Start at LOW, then apply bumps. HIGH is a cap.

- Baseline suite failing → set HIGH (stop; do not bump further)
- No test suite detected → set HIGH
- `>1` intermediate Ruby hop → bump one level
- `>1` intermediate Rails hop → bump one level
- Any native-extension gem lacking a target-compatible version → bump one level
- Monkey patches present in `config/initializers/` (grep `class .* < ` and `Module.prepend`) → bump one level

### Blast radius

Report concrete counts only — no ranges, no guesses:
- `N files, M call sites` for each scanned pattern
- `K gems` flagged by `bundle outdated`
- `L config files` expected to diff from `rails app:update` (Rails phase only)

### Confidence (LOW / MED / HIGH)

- HIGH — every input count was obtained automatically **and** baseline suite is green
- MED — some counts obtained but suite wasn't runnable, or one scan returned `unknown`
- LOW — suite not runnable **and** two or more counts are `unknown`

## Step 6: Generate the Plan

Output a Markdown-formatted plan with the following structure. Fill in specifics based on what was found in Steps 1–4.

---

### Plan header

```
# Ruby [CURRENT] → [TARGET] Upgrade Plan
# (+ Rails [CURRENT] → [TARGET] if rails: argument given)
Generated: [date]
App: [name from config/application.rb or directory name]
```

### Estimate Summary

| Phase | Effort | Risk | Blast radius | Confidence |
|-------|--------|------|--------------|------------|
| Phase 1: Ruby  | ~Xh   | LOW/MED/HIGH | N files, M sites, K gems | LOW/MED/HIGH |
| Phase 2: Rails | ~Xh   | LOW/MED/HIGH | N files, M sites, K gems | LOW/MED/HIGH |
| Phase 3: Verify | ~Xh  | LOW          | —                        | HIGH         |
| **Total**      | **~Xh** | **worst of above** | — | **lowest of above** |

Below the table, list the exact formulas used (e.g. `Phase 1 = 12 kwarg × 2min + 2 gems × 30min + 1 hop × 60min = 144min ≈ 2.5h`) so the user can audit or override.

### Phase 0: Prerequisites

- [ ] All current tests passing (`bundle exec rspec` or `bundle exec rails test`)
- [ ] Git branch created: `git checkout -b upgrade/ruby-[TARGET]`
- [ ] Current Ruby and Rails versions confirmed (from Step 1)
- [ ] CI pipeline configured to run on the upgrade branch

### Phase 1: Ruby Upgrade — [CURRENT_RUBY] → [TARGET_RUBY]

**Effort:** ~Xh · **Risk:** LOW/MED/HIGH · **Blast radius:** N files, M sites, K gems · **Confidence:** LOW/MED/HIGH

Repeat this phase for each intermediate Ruby version if multi-step.

#### 1a. Version Pins
- [ ] Update `.ruby-version` to `[TARGET_RUBY]`
- [ ] Update `ruby` directive in `Gemfile` to `"~> [TARGET_RUBY_MINOR]"`
- [ ] Install new Ruby: `rbenv install [TARGET_RUBY]` or `rvm install [TARGET_RUBY]`
- [ ] `bundle install`

#### 1b. Gem Updates for Ruby Compatibility
List each gem that needs a version bump for the target Ruby, with the required version and update command. Focus on gems with native extensions and known Ruby version constraints.

#### 1c. Ruby Version-Specific Code Changes
Based on the target Ruby version, list the code fixes required:

**2.7 → 3.0 (keyword argument separation):**
- Scan: `grep -rn "def .*\*\*" app/ lib/ --include="*.rb"`
- Fix each method where callers pass a plain hash where keywords are expected (add `**` at call site) or where a keyword method is called with `**{}` on a positional-hash method (remove `**`)
- YAML: `grep -rn "YAML\.load\b" app/ lib/ config/ --include="*.rb"` → replace with `YAML.safe_load`

**3.2 → 3.3 (`it` block parameter):**
- Scan: `grep -rn "\bit\b" app/ spec/ --include="*.rb" | grep -v "it ['\"]" | grep -v "#"`
- Rename any `it` variable inside blocks

**3.3 → 3.4 (stdlib gem removals):**
- Check for `require 'base64'`, `require 'csv'`, `require 'drb'`, `require 'mutex_m'`, `require 'nkf'`, `require 'bigdecimal'`
- Add each found library as explicit gem in Gemfile

#### 1d. Verify Phase 1
- [ ] `bundle exec rspec --no-color 2>&1 | tail -5` — must be green
- [ ] `bundle exec rubocop --parallel 2>&1 | tail -5` — must be clean
- [ ] `ruby -v` — confirms target Ruby active
- [ ] Run `/ruby-upgrade-toolkit:status` — must show GREEN

### Phase 2: Rails Upgrade — [CURRENT_RAILS] → [TARGET_RAILS]
*(Omit entirely if no `rails:` argument was given)*

**Effort:** ~Xh · **Risk:** LOW/MED/HIGH · **Blast radius:** N files, K gems, L config diffs · **Confidence:** LOW/MED/HIGH

Repeat for each intermediate Rails version if multi-step.

#### 2a. Gem Updates for Rails Compatibility
Cross-reference `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/compatibility-matrix.md`.
List each gem requiring a version bump with the required version and update command.

#### 2b. Rails Version Update
- [ ] Update `gem 'rails', '~> [TARGET_RAILS]'` in Gemfile
- [ ] `bundle update rails`
- [ ] `bin/rails app:update` — review each diff, apply selectively

#### 2c. Framework Defaults
- [ ] Set `config.load_defaults [TARGET_RAILS]` in `config/application.rb`
- [ ] Create `config/initializers/new_framework_defaults_[TARGET]_[MINOR].rb` stub to re-enable any defaults that break the app
- [ ] Enable defaults one at a time, run tests after each

#### 2d. Rails Version-Specific Deprecation Fixes
Based on the Rails version pair, load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/rails-[X]-to-[Y].md` and list the fixes that apply to this codebase. For each:
- What to grep for
- What to change
- Test command to verify

#### 2e. Verify Phase 2
- [ ] `bundle exec rspec --no-color 2>&1 | tail -5` — must be green
- [ ] `bundle exec rubocop --parallel 2>&1 | tail -5` — must be clean
- [ ] `bundle exec rails runner "puts Rails.version"` — confirms target Rails
- [ ] Run `/ruby-upgrade-toolkit:status` — must show GREEN

### Phase 3: Final Verification

**Effort:** ~1h · **Risk:** LOW · **Confidence:** HIGH

- [ ] Full test suite green
- [ ] Zero deprecation warnings: `RAILS_ENV=test bundle exec rspec 2>&1 | grep -c DEPRECATION || echo 0`
- [ ] Zero RuboCop offenses
- [ ] Staging deploy and smoke test
- [ ] Update CI/CD pipeline Ruby (and Rails) version — **manual step, list file paths**
- [ ] Update Dockerfile Ruby base image — **manual step, list file paths**

---

## Output

Print the complete plan. If the user has a preferred output path, write it to a file. Always include a `## Quick Commands` section at the end with copy-paste bash for each phase.
