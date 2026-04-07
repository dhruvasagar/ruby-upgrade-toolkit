---
name: Migration Safety Check
description: Use when the user runs /migration-safety-check or asks to check migration safety, audit database migrations, validate that migrations are safe to run in production, or identify risky schema changes before deploying an upgrade.
argument-hint: "[migration_file_or_directory] (optional, defaults to db/migrate/)"
allowed-tools: Read, Bash, Grep, Glob
version: 0.1.0
---

# Migration Safety Check

Audit database migrations for production safety issues: locking, zero-downtime compatibility, and data loss risks.

## Step 1: Identify Migrations to Check

```bash
# All migrations, newest first
ls -lt db/migrate/ | head -30

# Uncommitted/recent migrations (changes since last deploy)
git diff HEAD~10..HEAD --name-only -- db/migrate/ 2>/dev/null || ls db/migrate/ | tail -20
```

If a specific file or directory was passed as argument, scope the audit to that path.

## Step 2: Check Database Adapter

```bash
# Identify database (affects which operations are lock-safe)
grep -E "adapter:" config/database.yml | head -3
```

Lock behavior differs by database:
- **PostgreSQL**: Many DDL operations take `AccessExclusiveLock` — block all reads and writes
- **MySQL/MariaDB**: ALTER TABLE rewrites the table by default (use `pt-online-schema-change` or `gh-ost`)
- **SQLite**: Full table rewrite for most ALTERs (dev/test only — no production concern)

## Step 3: Read and Analyze Each Migration

For each migration file, read it and check against the risky patterns in `$CLAUDE_PLUGIN_ROOT/skills/migration-safety-check/references/risky-patterns.md`.

Apply these checks:

### Lock-causing operations (HIGH risk on large tables)

```
PATTERN: add_column with default value (Rails < 6.1 on PostgreSQL)
RISK: Rewrites entire table
FIX: Use add_column (no default) + update in batches + change_column_default

PATTERN: remove_column
RISK: Causes issues if old code still reads the column
FIX: First deploy code ignoring the column, then remove

PATTERN: rename_column
RISK: Old code breaks immediately
FIX: Add new column, backfill, update code, remove old column (4-step deploy)

PATTERN: change_column (type change)
RISK: Full table rewrite on PostgreSQL for most type changes
FIX: Add new column, backfill, swap

PATTERN: add_index without algorithm: :concurrently (PostgreSQL)
RISK: Locks table during index creation
FIX: add_index ..., algorithm: :concurrently (requires disable_ddl_transaction!)

PATTERN: add_reference / add_foreign_key without validate: false
RISK: Validates all existing rows — slow on large tables
FIX: add_foreign_key ..., validate: false then validate_foreign_key in a separate migration
```

### Data loss risk

```
PATTERN: remove_column (before code is updated)
PATTERN: drop_table
PATTERN: change_column null: false (without default or backfill)
PATTERN: irreversible migration without down method
```

### Missing safety guards

```ruby
# Check for disable_ddl_transaction! when needed
# Concurrent index creation REQUIRES this
```

## Step 4: Table Size Awareness

Large tables (> 1M rows or > 1GB) make any locking migration a production incident.

```bash
# PostgreSQL — check table sizes
bundle exec rails runner "
  ActiveRecord::Base.connection.tables.sort.each do |t|
    count = ActiveRecord::Base.connection.execute(\"SELECT reltuples::bigint FROM pg_class WHERE relname = '#{t}'\").first['reltuples'] rescue 0
    puts \"#{t}: ~#{count.to_i} rows\"
  end
" 2>/dev/null | sort -t: -k2 -rn | head -20
```

Flag any migration that touches a table with > 100k rows as **HIGH RISK** in production.

## Step 5: Reversibility Check

```bash
# Find irreversible migrations
grep -L "def down\|def change\|reversible" db/migrate/*.rb 2>/dev/null

# Find migrations using irreversible operations without safety guards
grep -rn "execute\|remove_column\|drop_table\|change_column" db/migrate/ | grep -v "reversible\|# safe"
```

## Step 6: Report

```
## Migration Safety Report
Date: [date]
Database: [adapter]
Migrations checked: [N]

### CRITICAL — Do Not Run Without Plan
[Migration file] — [reason] — [recommendation]

### HIGH — Risky on Large Tables
[Migration file] — table: [name] (~[N] rows) — [recommendation]

### MEDIUM — Review Before Deploying
[Migration file] — [reason] — [recommendation]

### LOW — Best Practice Notes
[Migration file] — [note]

### Safe to Deploy
[N] migrations have no identified risks

### Recommended Tools
- strong_migrations gem: adds automatic migration safety checks
- pg_ha_migrations: PostgreSQL-specific safe migration helpers
- LHM (Large Hadron Migrator): for MySQL large table changes
```

## Step 7: Recommend `strong_migrations` gem

If not already in the Gemfile, recommend adding:

```ruby
# Gemfile
gem 'strong_migrations'
```

`strong_migrations` blocks unsafe operations at the Rails level and shows the safe alternative. It catches most of what this audit does automatically in future migrations.
