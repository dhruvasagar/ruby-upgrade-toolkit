# Intermediate Upgrade Paths

Rules for sequencing multi-minor-version upgrades. Used by the `plan`, `audit`, and `upgrade` skills to compute the list of intermediate phases.

**Core rule:** never skip an intermediate minor version. Each intermediate step must have a green test suite before proceeding to the next.

## Ruby paths

Step through every minor version between current and target.

| From | To  | Path                              |
|------|-----|-----------------------------------|
| 2.6  | 3.0 | 2.6 → 2.7 → 3.0                   |
| 2.7  | 3.3 | 2.7 → 3.0 → 3.1 → 3.2 → 3.3       |
| 3.0  | 3.4 | 3.0 → 3.1 → 3.2 → 3.3 → 3.4       |
| 3.1  | 3.3 | 3.1 → 3.2 → 3.3                   |
| 3.2  | 3.3 | 3.2 → 3.3 (single hop)            |

Always use the latest stable patch of each intermediate minor — patch releases carry security fixes.

## Rails paths

Same rule — never skip a minor.

| From | To  | Path                        |
|------|-----|-----------------------------|
| 5.2  | 7.1 | 5.2 → 6.0 → 6.1 → 7.0 → 7.1 |
| 6.1  | 8.0 | 6.1 → 7.0 → 7.1 → 8.0       |
| 7.0  | 8.0 | 7.0 → 7.1 → 8.0             |
| 7.1  | 8.0 | 7.1 → 8.0 (single hop)      |

## Ordering Ruby and Rails together

When both Ruby and Rails upgrade in the same engagement:

1. Complete **all** Ruby phases first — the final Ruby target must be GREEN.
2. Then start Rails phases.

**Why:** Rails version bumps interact with gem dependencies that have Ruby-version constraints. Settling the Ruby binary first produces a single axis of change per Rails phase and makes test regressions trivially attributable.

## Latest stable patch hints

Known-good patches per minor (update as new patches release):

| Minor | Latest patch |
|-------|--------------|
| Ruby 3.0.x | 3.0.7 |
| Ruby 3.1.x | 3.1.6 |
| Ruby 3.2.x | 3.2.4 |
| Ruby 3.3.x | 3.3.1 |
| Ruby 3.4.x | check ruby-lang.org |

If the user passes `ruby:X.Y.Z` with an explicit patch, use that exact patch for the final step. For intermediate steps where only a minor is relevant, use the latest stable patch of that minor.

## Single-phase shortcut

If current minor == target minor (same-minor patch bump, e.g. 3.2.3 → 3.2.4), there is no intermediate path — run a single phase.
