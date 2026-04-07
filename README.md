# claude-rails-upgrade

A comprehensive Claude Code plugin for upgrading Rails applications. Version-agnostic — supports any upgrade path: Rails 5→6, 6→7, 7→8, and patch releases.

## What It Does

This plugin gives Claude structured, repeatable methodology for the full Rails upgrade lifecycle:

| Phase | Skill | Description |
|-------|-------|-------------|
| Plan | `/upgrade-plan` | Generate a phased upgrade plan for any version pair |
| Audit | `/deprecation-audit` | Capture all deprecation warnings (dynamic + static) |
| Gems | `/gem-compatibility-check` | Identify gems that need updating |
| Config | `/config-upgrade` | Migrate Rails configuration defaults |
| Fix | `/fix-deprecations` | Apply automated and guided deprecation fixes |
| Safety | `/migration-safety-check` | Audit migrations for production safety |
| Track | `/upgrade-status` | Current health report and progress |

Plus two autonomous agents:

- **upgrade-auditor** — Proactively runs a full pre-upgrade audit when you start upgrade work
- **deprecation-fixer** — Autonomously fixes deprecation warnings file-by-file

## Installation

### Via Claude Code marketplace

```bash
cc --plugin install claude-rails-upgrade
```

### Local development / manual

```bash
git clone https://github.com/dhruvasagar/claude-rails-upgrade
cc --plugin-dir /path/to/claude-rails-upgrade
```

## Usage

### Start an upgrade

```
/upgrade-plan 6.1 7.1
```

Claude will generate a phased plan tailored to your specific app.

### Full pre-upgrade audit (agent)

Just tell Claude you're starting an upgrade:
> "I need to upgrade this app from Rails 7.0 to Rails 8.0"

The **upgrade-auditor** agent activates automatically and produces a complete findings report.

### Check your current state

```
/upgrade-status
```

### Fix deprecation warnings

```
/fix-deprecations app/models/user.rb
/fix-deprecations app/controllers/
```

### Check gem compatibility

```
/gem-compatibility-check 8.0
```

### Audit migration safety

```
/migration-safety-check
/migration-safety-check db/migrate/20240315_add_index_to_users.rb
```

### Update configuration

```
/config-upgrade 8.0
```

## Hooks

Three automatic safety hooks activate when the plugin is installed:

| Hook | Event | Behavior |
|------|-------|---------|
| block-vendor | PreToolUse (Write/Edit) | Blocks any write to `vendor/` — use `bundle update` instead |
| log-migration | PostToolUse (Write/Edit) | Logs all changes to `db/migrate/` files to `upgrade_audit.log` |
| rubocop-fix | PostToolUse (Write/Edit) | **Opt-in** — auto-corrects Style/Layout cops on edited `.rb` files |

### Enable Rubocop Auto-fix

The rubocop hook is off by default. To enable:

```bash
touch .rails-upgrade-rubocop
```

To disable:

```bash
rm .rails-upgrade-rubocop
```

Requires `rubocop` in your Gemfile.

## Version Guides

The plugin includes curated breaking-changes guides for:

- [Rails 5 → 6](skills/rails-upgrade-guide/references/rails-5-to-6.md)
- [Rails 6 → 7](skills/rails-upgrade-guide/references/rails-6-to-7.md)
- [Rails 7 → 8](skills/rails-upgrade-guide/references/rails-7-to-8.md)

And a [gem compatibility matrix](skills/gem-compatibility-check/references/compatibility-matrix.md) covering 40+ common gems.

## CI Template

A GitHub Actions workflow template is included at `.github/workflows/rails-upgrade-ci.yml`.

Copy it to your application's `.github/workflows/` directory to get:
- Test runs on upgrade branches
- Deprecation warning counts in CI output
- Zeitwerk compliance checks
- Migration pattern safety scan

## Prerequisites

- Claude Code 1.x+
- Ruby project using Bundler
- `jq` installed (for hook scripts): `brew install jq` / `apt install jq`

## Contributing

Issues and PRs welcome at [github.com/dhruvasagar/claude-rails-upgrade](https://github.com/dhruvasagar/claude-rails-upgrade).

To add a new version guide (e.g. Rails 8 → 9), add a file at `skills/rails-upgrade-guide/references/rails-8-to-9.md` following the existing format.

To extend the gem compatibility matrix, edit `skills/gem-compatibility-check/references/compatibility-matrix.md`.

## License

MIT
