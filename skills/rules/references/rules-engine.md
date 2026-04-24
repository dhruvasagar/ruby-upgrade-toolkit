# Rules Engine — Shared Load/Validate/Apply Reference

Single source of truth for how `rules.yml` is loaded, validated, and applied.

Consumed by:
- `skills/rules/SKILL.md` — for all `/rules` subcommands
- `skills/audit/SKILL.md` — at the start of every audit
- `skills/plan/SKILL.md` — during path computation and phase rendering
- `skills/fix/SKILL.md` — during apply and verify
- `skills/upgrade/SKILL.md` — during preflight and recovery
- `skills/status/SKILL.md` — for the "Custom gates" section

All five consuming skills follow this reference — the algorithms are
identical across entry points by design.

---

## Load

```bash
test -f .ruby-upgrade-toolkit/rules.yml
```

If the file does **not** exist:
- Set `RULES_LOADED = false`, `RULES = []`, `DEFAULTS = {}`.
- Exit the load step. The rest of the calling skill proceeds as if this
  feature didn't exist — **zero behavior change**. This is the backward-
  compatibility guarantee.

If the file exists:
- Read it with the Read tool.
- Parse as YAML. Parse failures are a **hard error** (print the parser
  error, mark the whole skill run as failed, stop).
- Set `RULES_LOADED = true`.
- Extract `version`, `defaults`, `rules` top-level keys.
- If `version != 1`, print:
  ```
  rules.yml declares version N, but this plugin supports version 1.
  Update the plugin or downgrade the file.
  ```
  and stop.

Validate each rule structurally against `schema.md` (see "Schema check"
below).

## Schema check

For each rule in `rules`:

1. **Required fields.** `id` and `type` must be present. Missing → error.
2. **`id` uniqueness.** If two rules share an `id`, error on the second one.
3. **`type` enum.** Must be one of the eight known types. Unknown → error.
4. **Type-specific required fields.** Apply the table from `schema.md`
   "Field schema per type" for the given `type`. Missing required field → error.
5. **`enabled` type.** If present, must be boolean. Otherwise default `true`.
6. **`when.phases` shape.** If present, must be a non-empty list of strings.
   Each string: `all`, `ruby-phases`, `rails-phases`, `final`, `ruby:<X.Y.Z>`,
   or `rails:<X.Y>`. Unknown phase spec → error.
7. **Per-type validation.**
   - `gem-constraint`: constraint is a parseable Bundler version requirement.
     `mode: forbid` + `constraint` present → warning.
   - `gem-swap`: `to` non-empty; `from` ≠ any `to[].name`.
   - `target-substitute`: `target: rails` (v1); `replacement.source.credentials_env`
     matches `^[A-Z][A-Z0-9_]*$` if present.
   - `code-transform` / `gem-swap.code_transforms[]`: `mode: regex` patterns
     compile; run the catastrophic-backtracking check (see "Pattern safety"
     below).
   - `phase-inject.action` / `verification-gate.command`: single-command
     check (see "Command safety" below).
   - `policy-override.setting` is in the v1 whitelist; `value` type matches.
   - `intermediate-pin`: exactly one of `ruby`/`rails` set.

## Conflict detection

Run after schema check. These are warnings, not errors — the user may
intentionally layer rules.

- **Two `target-substitute` with the same `target`.** Error, not warning.
- **Two rules with the same `gem` target (`gem-constraint`, `gem-swap.from`,
  or `gem-swap.to[].name`).** Warning: "Rule <later-id> overrides <earlier-id>
  for gem <name>. Later rule wins."
- **`gem-constraint` on a gem that another rule `gem-swap`s away.** Warning:
  "Constraint on <gem> has no effect — it will be removed by the
  <swap-id> swap."
- **Two `verification-gate`s with identical `command`.** Error if their
  `required` values differ (ambiguous); warning otherwise.

## Preflight (credentials)

For each rule that references a private gem source:
- `target-substitute.replacement.source.credentials_env`
- `gem-swap.to[].source.credentials_env`

Check:
```bash
test -n "${ENV_VAR_NAME}"
```

- At `validate`/`list`/`show`/`explain` time: missing env var is a **warning**.
- At `audit` time: missing env var is an **error** for that specific rule
  (other rules continue), and the rule is flagged as "will fail at upgrade
  preflight."
- At `upgrade` Step 5 preflight: missing env var is a **hard error** — the
  upgrade cannot start. The message lists every missing var and the command
  to fix each one:
  ```
  Cannot start upgrade: 2 rules require credentials that are not set.

    [rails-lts-substitute]    needs BUNDLE_RAILSLTS__COM
      Set it: bundle config railslts.com <creds>
              export BUNDLE_RAILSLTS__COM='<creds>'

    [sidekiq-to-pro]          needs BUNDLE_GEMS__CONTRIBSYS__COM
      Set it: bundle config gems.contribsys.com <creds>

  Or temporarily disable the offending rules:
    /ruby-upgrade-toolkit:rules disable rails-lts-substitute
    /ruby-upgrade-toolkit:rules disable sidekiq-to-pro
  ```

**Never log the env var's value**, only its name and set/unset state.

## Pattern safety (code-transform `mode: regex`)

For any pattern with `mode: regex`:

1. Compile as Ruby `Regexp.new(pattern)`. Compilation failure → error with
   the compiler message.
2. Reject patterns that are likely catastrophic on user input. Heuristics:
   - Nested quantifiers (`(.+)+`, `(\w*)*`) — error.
   - Alternation with overlapping prefixes (e.g., `(a|a)*`) — error.
   - Unbounded lookahead/lookbehind followed by quantifier — warning.
3. `files` globs must not include `vendor/**` — strip and warn.

## Command safety (phase-inject `action`, verification-gate `command`)

For every `action` / `command` string:

1. Tokenize with POSIX shell rules.
2. Reject if the raw string contains any of these outside single-quoted
   substrings: `|`, `;`, `&&`, `||`, `>`, `<`, `` ` ``, `$(`.
3. The first token must resolve to an executable (bundle, rake, rails, or
   a path to a script). No executable resolution happens at validate time —
   only the syntactic check. At `explain` and `fix` time, do a `command -v`
   check and surface missing binaries.

## Rule resolution (for `plan` and `fix`)

Given a phase and the list of active rules:

1. Expand `when.phases`:
   - `all` → matches every apply phase + Final.
   - `ruby-phases` → matches every `ruby:X.Y.Z` apply phase.
   - `rails-phases` → matches every `rails:X.Y` apply phase.
   - `ruby:X.Y.Z` / `rails:X.Y` → matches that specific phase only.
   - `final` → matches the Final phase only.
2. For each rule whose expanded `when.phases` includes the current phase,
   check applicability:
   - `gem-constraint`: always applicable within its matching phases.
   - `gem-swap`: applicable only if `from` gem is present in the Gemfile.
   - `target-substitute`: applicable only if target matches the phase
     language (e.g., `target: rails` during Rails phases or path computation).
   - `code-transform` / `gem-swap.code_transforms[]`: applicable only if
     `pattern` matches at least one file under the effective globs.
   - `phase-inject`: applicable within its matching phases regardless of
     state.
   - `verification-gate`: applicable within its matching phases; binary check
     gates applicability — missing binary + `required: true` → error,
     missing binary + `required: false` → skip with warning.
   - `policy-override`: applied globally once loaded, not per-phase.
   - `intermediate-pin`: consumed only by `plan` during path computation.
3. Collect the applicable rules per phase. Render according to the calling
   skill's output format (e.g., `plan` uses `[rule: <id>]` tags).

## Apply ordering (for `fix`)

Within a phase's apply step:

1. All `phase-inject` rules with `timing: before` matching this phase, in
   declared order.
2. Built-in apply steps (version pins, gem bumps, Ruby/Rails fixes from
   existing SKILL.md).
3. All `code-transform` rules matching this phase, in declared order.
4. All `gem-swap` rules matching this phase (edit Gemfile, run
   `bundle install`, apply the swap's `code_transforms[]`), in declared order.
5. All `phase-inject` rules with `timing: after` matching this phase, in
   declared order.

Within a phase's verify step:

1. All `verification-gate` rules with `timing: before` matching this phase,
   in declared order.
2. Built-in gates (RSpec, RuboCop, deprecation count).
3. All `verification-gate` rules with `timing: after` matching this phase,
   in declared order.

Each verification gate:
- Runs the `command`. Captures exit code and last 40 lines of output.
- Exit 0 → gate passed.
- Non-zero + `required: true` → phase fails (RED), skip the commit prompt,
  surface the gate output and exit.
- Non-zero + `required: false` → mark gate as "advisory: FAILED", continue
  to next gate / next step; include the outcome in the commit message.

## Commit message contribution (for `fix`)

After a successful phase, append a "Custom rules applied" block to the
proposed commit message. Format:

```
Custom rules applied:
- [phantomjs-to-selenium] Swapped phantomjs → selenium-webdriver, webdrivers. Rewrote 2 Capybara config sites.
- [devise-pin] Constraint '>= 4.9' enforced during bundle resolution.
- [brakeman-gate] Passed (0 warnings).
- [reek-gate] 14 offenses (advisory — not blocking).
```

Every rule that fired — including no-ops that were checked — should be
listed, even if only "no changes made." This makes the commit self-
documenting for future readers.

## Rules that never fired

At the end of a `fix` or `upgrade` run, if the user has any rules that
produced zero effect across all phases, surface them as an informational
line:

```
Rules that did not fire in this run:
  - [logger-rename] code-transform — pattern matched 0 sites in any phase
```

Do not block — the user may have legitimate reasons (future-phase-only
rules, branch-specific rules, etc.). Just report.
