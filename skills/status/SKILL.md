---
name: Upgrade Status
description: Use when the user runs /ruby-upgrade-toolkit:status or asks for the current upgrade status, upgrade progress report, whether the upgrade is complete, or a summary of what's done and what's remaining. No arguments — detects everything from the project state. Produces a RED/YELLOW/GREEN health report.
argument-hint: "(no arguments)"
allowed-tools: Read, Bash, Glob, Grep
version: 0.2.0
---

# Upgrade Status

Generate a health dashboard for the current state of the upgrade. Run this after each fix phase to confirm readiness before proceeding.

This skill is a thin consumer of the canonical verification commands — load `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/verification-suite.md` once at the start and use its blocks for each step below.

## Step 0: Load custom rules (if present)

Apply the "Load" section of
`$CLAUDE_PLUGIN_ROOT/skills/rules/references/rules-engine.md`.

If `.ruby-upgrade-toolkit/rules.yml` is absent, set `RULES_LOADED = false`
and skip the Custom gates section in Step 8 — the report is byte-identical
to pre-rules behavior.

If rules are loaded, collect the active `verification-gate` rules whose
`when.phases` includes the current project's state (use the engine's "Rule
resolution" section). These will be run and reported in Step 8.

## Step 1: Detect Versions

```bash
ruby -v 2>/dev/null || echo "Ruby: unknown"
cat .ruby-version 2>/dev/null
grep "^ruby " Gemfile 2>/dev/null
bundle exec rails -v 2>/dev/null || echo "Rails: not present"
grep "load_defaults" config/application.rb 2>/dev/null || true
git branch --show-current 2>/dev/null
```

## Step 2: Test Suite

Use the "Test suite — full run" block from the verification suite reference.

## Step 3: Deprecation Warning Count

Use the "Deprecation warnings" block (simple counter form) from the verification suite reference.

## Step 4: Ruby Warning Count

Use the "Ruby warnings" block from the verification suite reference.

## Step 5: RuboCop Status

Use the "RuboCop — offense count (JSON)" block from the verification suite reference.

## Step 6: Gem Compatibility Signal

Use the "Outdated gems signal" block from the verification suite reference.

## Step 7: Zeitwerk (Rails only)

Use the "Zeitwerk" block from the verification suite reference.

## Step 8: Render the Report

```
# Upgrade Status Report
Generated: [datetime]
Branch: [branch name]

## Versions
| | Current | Target |
|-|---------|--------|
| Ruby | [current] | [from .ruby-version or user context] |
| Rails | [current] | [from Gemfile or user context] |
| load_defaults | [value] | — |

## Test Suite
- Status: [PASSING / FAILING / NOT FOUND]
- [N] examples, [F] failures, [P] pending

## Warnings
- Deprecation warnings: [N]
- Ruby warnings: [N]
- RuboCop offenses: [N]

## Gem Health
- Outdated gems: [N]

## Zeitwerk (Rails only)
- [OK / N errors]

## Custom gates (include only if RULES_LOADED is true AND active verification-gate rules exist)
For each active verification-gate rule:
- Run the gate's `command`, capture exit code + last 40 lines.
- Exit 0 → `[rule-id] PASS`
- Non-zero + required → `[rule-id] FAIL (required) — see output below`, contributes to RED tier
- Non-zero + advisory → `[rule-id] ADVISORY (N issues, not blocking)`, does NOT affect tier

Render as:
```
## Custom gates
- [brakeman-gate] PASS (required)
- [reek-gate] ADVISORY 14 issues (not blocking)
```

## Overall Readiness: [RED / YELLOW / GREEN]

See "Readiness tiers" in `$CLAUDE_PLUGIN_ROOT/skills/rails-upgrade-guide/references/verification-suite.md` for the canonical tier definitions.

## Suggested Next Step
[Most actionable next step based on the report]
[Command to run]
```
