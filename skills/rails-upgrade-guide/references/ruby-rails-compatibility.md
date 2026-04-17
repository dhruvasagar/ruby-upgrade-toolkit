# Ruby ↔ Rails Compatibility Matrix

Minimum and recommended Rails version for each Ruby version. Used by the `plan`, `audit`, and `upgrade` skills to validate that a combined target (`ruby:X.Y.Z rails:X.Y`) is viable before any work begins.

## Matrix

| Target Ruby | Minimum Rails | Recommended Rails |
|-------------|---------------|-------------------|
| 2.7         | 5.2           | 6.0–6.1           |
| 3.0         | 6.1           | 7.0               |
| 3.1         | 7.0           | 7.0–7.1           |
| 3.2         | 7.0.4         | 7.1               |
| 3.3         | 7.1           | 7.1–7.2           |
| 3.4         | 7.2           | 7.2–8.0           |

## How to validate

1. If no `rails:` argument is provided, skip this check entirely.
2. Look up the target Ruby row.
3. If the requested Rails version is **below** the Minimum Rails cell, surface an incompatibility error and stop — do not generate a plan or start an upgrade.
4. If the requested Rails version is at or above Minimum but **below** Recommended, surface a soft warning and allow the upgrade to proceed.

## Error template (hard incompatibility)

```
⛔ Incompatible target: Ruby [TARGET_RUBY] requires Rails >= [MIN_RAILS].
   You asked for Rails [TARGET_RAILS].

   Valid options:
     • Upgrade Rails to [MIN_RAILS]+ first, or
     • Target an older Ruby version that supports Rails [TARGET_RAILS]
```

## Warning template (soft incompatibility)

```
⚠️  Ruby [TARGET_RUBY] + Rails [TARGET_RAILS] is supported but not recommended.
    Recommended Rails for this Ruby: [RECOMMENDED_RAILS].
    Proceeding — you may hit edge-case deprecations sooner on the unsupported combination.
```
