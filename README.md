# ruby-upgrade-toolkit

A Claude Code plugin for upgrading Ruby projects safely — including Ruby on Rails apps. Supports any Ruby version upgrade (2.7→3.x and beyond) and any Rails version upgrade (5→8), separately or together.

## How It Works

The plugin gives Claude a structured, repeatable methodology through four commands that map to a canonical workflow:

```
audit → plan → fix → status
```

**Why this order matters:**
- `audit` is read-only — zero risk, run it first to understand the full scope before touching code
- `plan` uses audit findings to sequence work correctly — Ruby phases before Rails phases, intermediate versions before final target
- `fix` applies changes phase by phase — gem updates, code fixes, then iterative RSpec and RuboCop until green
- `status` is your checkpoint after each fix phase — confirms green before you proceed

## Installation

### Via Claude Code marketplace

```bash
/plugin marketplace add dhruvasagar/ruby-upgrade-toolkit
```

### Local development

```bash
git clone https://github.com/dhruvasagar/ruby-upgrade-toolkit
/plugin local add /path/to/ruby-upgrade-toolkit
```

## Command Reference

All commands are namespaced under `/ruby-upgrade-toolkit:` to avoid conflicts with other plugins.

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

Generate a phased, project-specific upgrade roadmap. Detects current versions automatically.

Produces a Markdown plan with: prerequisites, Ruby upgrade phases (one per intermediate version), Rails upgrade phases (if `rails:` given), and a final verification checklist. Each phase ends with RSpec green + RuboCop clean.

```bash
# Ruby-only plan
/ruby-upgrade-toolkit:plan ruby:3.3.1

# Combined Ruby + Rails plan
/ruby-upgrade-toolkit:plan ruby:3.3.1 rails:8.0
```

### `/ruby-upgrade-toolkit:fix ruby:X.Y.Z [rails:X.Y] [scope:path]`

Apply all upgrade changes. The primary execution command.

Applies: `.ruby-version` and `Gemfile` pin updates, gem dependency updates, Ruby version-specific code fixes, Rails deprecation fixes (if `rails:` given), Rails config updates (if `rails:` given), iterative RSpec until green, iterative RuboCop until clean.

Flags CI/CD pipeline files and Dockerfiles for manual update — never modifies them automatically.

```bash
# Fix Ruby upgrade
/ruby-upgrade-toolkit:fix ruby:3.3.1

# Fix Ruby + Rails upgrade
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0

# Fix a single file only (gem/pin changes still apply project-wide)
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/models/user.rb

# Fix a directory
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/controllers/
```

### `/ruby-upgrade-toolkit:status`

Current upgrade health dashboard. No arguments.

Reports: current vs. target versions, test suite pass/fail, deprecation warning count, Ruby warning count, RuboCop offense count, and overall RED/YELLOW/GREEN readiness.

Run this after each `fix` phase. Do not proceed to the next phase if the report shows RED.

```bash
/ruby-upgrade-toolkit:status
```

## Canonical Workflow Examples

### Example 1: Ruby-only upgrade (2.7 → 3.3)

```bash
# 1. Understand the scope
/ruby-upgrade-toolkit:audit ruby:3.3.1

# 2. Generate the roadmap (includes intermediate: 2.7→3.0→3.1→3.2→3.3)
/ruby-upgrade-toolkit:plan ruby:3.3.1

# 3. Apply the first phase (2.7 → 3.0, the most impactful step)
/ruby-upgrade-toolkit:fix ruby:3.0.7

# 4. Checkpoint — must be GREEN before next phase
/ruby-upgrade-toolkit:status

# 5. Continue phase by phase until 3.3.1
/ruby-upgrade-toolkit:fix ruby:3.1.6
/ruby-upgrade-toolkit:status
/ruby-upgrade-toolkit:fix ruby:3.2.4
/ruby-upgrade-toolkit:status
/ruby-upgrade-toolkit:fix ruby:3.3.1
/ruby-upgrade-toolkit:status
```

### Example 2: Coordinated Ruby + Rails upgrade

```bash
# 1. Full audit of both upgrade targets
/ruby-upgrade-toolkit:audit ruby:3.3.1 rails:8.0

# 2. Phased plan (Ruby first, then Rails)
/ruby-upgrade-toolkit:plan ruby:3.3.1 rails:8.0

# 3. Complete the Ruby upgrade first
/ruby-upgrade-toolkit:fix ruby:3.3.1
/ruby-upgrade-toolkit:status  # must be GREEN

# 4. Then apply the Rails upgrade
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0
/ruby-upgrade-toolkit:status  # must be GREEN
```

### Example 3: Targeted fix during an upgrade

```bash
# Fix a specific model that has deprecation warnings
/ruby-upgrade-toolkit:fix ruby:3.3.1 rails:8.0 scope:app/models/order.rb

# Check progress
/ruby-upgrade-toolkit:status
```

### Example 4: Check current state at any time

```bash
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
