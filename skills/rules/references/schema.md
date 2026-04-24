# Rules Schema Reference

Canonical data model for `.ruby-upgrade-toolkit/rules.yml`.

Loaded by:
- `skills/rules/SKILL.md` (for `validate`, `add`, `show`)
- `skills/rules/references/rules-engine.md` (load/parse pipeline)
- The consuming skills (`audit`, `plan`, `fix`, `upgrade`, `status`)

---

## File structure

```yaml
version: 1                    # required; integer; current schema version
defaults:                     # optional; whitelisted policy knobs (see "policy-override" below)
  require_rubocop: true
  baseline_failures_allowed: 0
rules:                        # optional but typical; ordered list
  - id: …
    type: …
    …
```

Top-level keys:

| Key | Required | Type | Notes |
|-----|----------|------|-------|
| `version` | yes | integer | Current = 1. Future schema changes bump this. |
| `defaults` | no | map | Shortcut for common `policy-override` values. See policy-override below. |
| `rules` | no | list | Each entry is a rule object (see types below). Order matters for conflict resolution. |

Any unknown top-level key is a **validation error**.

## Common fields (every rule)

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `id` | yes | string | — | Unique within the file. Kebab-case by convention. Used by `show`/`remove`/`disable`/`enable` subcommands. |
| `type` | yes | enum | — | One of the eight types below. |
| `description` | no | string | `""` | Human-readable rationale. Strongly encouraged. |
| `enabled` | no | bool | `true` | When false, the rule is ignored everywhere except `list --all` and `show`. |
| `when` | no | map | `{ phases: [all] }` | Scoping clause (see "when clause" below). |

### `when` clause

Scopes a rule to specific phases. All phases means "every apply phase plus
the Final phase."

```yaml
when:
  phases: [all]                      # default — fires in every apply phase
  phases: [ruby-phases]              # only Ruby apply phases
  phases: [rails-phases]             # only Rails apply phases
  phases: [ruby:3.3, rails:7.0]      # specific phase targets (by version)
  phases: [final]                    # only the Final infra phase
```

Validation:
- `phases` must be a non-empty list of strings.
- Each string is either a keyword (`all`, `ruby-phases`, `rails-phases`,
  `final`) or a phase spec (`ruby:<X.Y.Z>` or `rails:<X.Y>`).
- Mixing `all` with any other phase is a warning (the other is redundant).

## Field schema per type

### `gem-constraint`

Pin, cap, floor, or forbid a gem during bundle resolution.

```yaml
- id: devise-min-version
  type: gem-constraint
  gem: devise                         # required; gem name
  constraint: '>= 4.9'                # required unless mode: forbid
  mode: require                       # optional; 'require' (default) or 'forbid'
  description: "Required for Rails 7+ compatibility"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `gem` | yes | string | — | Gem name. Must match the Gemfile entry's first argument. |
| `constraint` | yes if `mode: require` | string | — | A valid Bundler version constraint (`>= X.Y`, `~> X.Y`, `= X.Y.Z`, ranges allowed). |
| `mode` | no | enum | `require` | `require` enforces the constraint; `forbid` makes presence of the gem an error. |

Validation:
- `constraint` is parsed using Bundler version-requirement syntax. Invalid
  syntax is an error.
- `mode: forbid` + `constraint` present → warning: the constraint has no
  effect when forbidding presence.

### `gem-swap`

Replace gem X with gem Y (possibly a list of gems), optionally bundling code
rewrites that make the application work with the new gem.

```yaml
- id: phantomjs-to-selenium
  type: gem-swap
  from: phantomjs                     # required; gem to remove
  to:                                  # required; list of gems to add (may be 1)
    - name: selenium-webdriver
      constraint: '~> 4.0'
    - name: webdrivers
      constraint: '~> 5.0'
  code_transforms:                     # optional; applied during the phase's apply step
    - pattern: "Capybara.javascript_driver = :poltergeist"
      replacement: "Capybara.javascript_driver = :selenium_chrome_headless"
      mode: literal                    # optional; 'literal' (default) or 'regex'
      files: ["spec/**/*.rb"]          # optional; glob restriction
  description: "Replace phantomjs with selenium + headless chromium"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `from` | yes | string | — | Gem to remove. |
| `to` | yes | list | — | Each entry: `{ name, constraint, source? }`. `name` required, `constraint` optional (omitted = latest). |
| `to[].source` | no | map | — | `{ url, credentials_env }` — see "Private gem sources" below. |
| `code_transforms` | no | list | `[]` | Each entry has `pattern`, `replacement`, optional `mode`, optional `files`. See `code-transform` type below for field semantics. |

Validation:
- `from` must not equal any `to[].name` (would self-swap — error).
- `to` must be non-empty.
- If the same gem appears in another rule's `gem-constraint`, the constraint
  only applies to matching `to[].name` entries; otherwise warn "constraint
  ineffective with this swap."

### `target-substitute`

Redirect the upgrade target itself. Distinct from `gem-swap` because it
changes what `plan`'s sequencer computes as the upgrade destination — not
just a dependency swap.

```yaml
- id: rails-lts-substitute
  type: target-substitute
  target: rails                        # required; 'rails' (v1 only; 'ruby' reserved for future)
  replacement:                         # required
    gem: railslts-version
    constraint: '~> 6.1.7'
    source:
      url: https://railslts.com
      credentials_env: BUNDLE_RAILSLTS__COM
  description: "Use Rails LTS 6.1 (paid backports) instead of mainline Rails upgrades"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `target` | yes | enum | — | Currently only `rails` is supported in v1. `ruby` is reserved. |
| `replacement.gem` | yes | string | — | Gem name that replaces the target. |
| `replacement.constraint` | yes | string | — | Version constraint. |
| `replacement.source` | no | map | — | `{ url, credentials_env }` for private sources. |

Validation:
- Only **one** `target-substitute` per `target` is allowed. Two rules with
  `target: rails` is an error.
- `replacement.source.credentials_env` must be a valid env var name
  (uppercase + digits + `_`).
- `plan`'s path computation changes: the upgrade target for `target: rails`
  becomes `replacement.gem @ replacement.constraint` instead of mainline
  Rails. Intermediate Rails hops are skipped.

### `code-transform`

Standalone code rewrite rule. Similar to the `code_transforms` field inside
`gem-swap`, but applied independently (not tied to a gem change).

```yaml
- id: logger-rename
  type: code-transform
  pattern: "MyApp::LegacyLogger.log"
  replacement: "Rails.logger.info"
  mode: literal                        # 'literal' (default) or 'regex'
  files: ["app/**/*.rb", "lib/**/*.rb"]
  description: "Retire the legacy logger wrapper"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `pattern` | yes | string | — | Literal string (default) or regex (if `mode: regex`). |
| `replacement` | yes | string | — | Literal replacement string. |
| `mode` | no | enum | `literal` | `literal` = exact string match; `regex` = Ruby regex (must validate at authoring time). |
| `files` | no | list of glob strings | `["app/**/*.rb", "lib/**/*.rb", "spec/**/*.rb", "test/**/*.rb", "config/**/*.rb"]` | Restrict to these globs; `vendor/` is always excluded. |

Validation:
- `mode: regex` — the pattern must compile as a Ruby regex and must pass a
  catastrophic-backtracking check (using `safe-regex` heuristics). Failure
  is an error.
- `vendor/**` in `files` is stripped with a warning — the block-vendor hook
  prevents writes there regardless.

### `phase-inject`

Insert a shell command into a specific phase's apply step, either before or
after the built-in apply actions.

```yaml
- id: dump-schema-cache
  type: phase-inject
  phase: rails:7.0                     # required; specific phase or 'all'
  timing: before                       # required; 'before' or 'after'
  action: "bundle exec rails db:schema:cache:dump"
  description: "Refresh schema cache before Rails 7 activates strict loading"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `phase` | yes | string | — | `ruby:<X.Y.Z>`, `rails:<X.Y>`, `all`, `final`, `ruby-phases`, `rails-phases`. |
| `timing` | yes | enum | — | `before` (runs before built-in apply) or `after` (runs after). |
| `action` | yes | string | — | Single shell command. No pipes (`\|`), redirects (`>`, `<`), or `&&`/`;` chaining in v1. |
| `as` | no | enum | `inline` | `inline` = just an extra apply step; `standalone` = promote to its own TodoWrite task row. |

Validation:
- `action` is parsed with a strict single-command tokenizer. Any shell
  metacharacter outside single-quoted strings is an error.
- A `phase-inject` with `phase: final` and `timing: before` is unusual
  (Final has no apply step) — warn.

### `verification-gate`

Extra verification command that must (or may) pass as part of reaching
GREEN.

```yaml
- id: brakeman-gate
  type: verification-gate
  command: "bundle exec brakeman --no-pager --exit-on-warn"
  when: { phases: [all] }
  timing: after                        # 'before' or 'after' built-in gates
  required: true                       # must pass to reach GREEN
  description: "Every phase must pass Brakeman before commit"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `command` | yes | string | — | Single shell command (same restrictions as `phase-inject.action`). |
| `timing` | no | enum | `after` | `before` = runs before RSpec/RuboCop; `after` = after them. |
| `required` | no | bool | `true` | `true` = fail blocks GREEN; `false` = advisory only (logged, never blocks commit). |

Validation:
- If two gates have the same `command` with different `required` values,
  error (ambiguous).

### `policy-override`

Tweak a whitelisted toolkit default.

```yaml
- id: no-rubocop
  type: policy-override
  setting: rubocop.enabled
  value: false
  description: "RuboCop runs separately in CI"
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `setting` | yes | string | — | One of the whitelisted keys (below). |
| `value` | yes | varies | — | Type must match the setting's type. |

**v1 whitelist:**

| Setting | Type | Default | Effect |
|---------|------|---------|--------|
| `rubocop.enabled` | bool | `true` | When `false`, skip the RuboCop step in `fix` and the RuboCop row in `status`. |
| `baseline_failures_allowed` | int | `0` | Number of test failures allowed in the baseline before `audit` escalates risk. |
| `require_zero_deprecations` | bool | `false` | When `true`, any deprecation warning blocks GREEN. |
| `require_zeitwerk_clean` | bool | `true` | (Rails only) Require `rails zeitwerk:check` to exit cleanly. |

Any setting outside the whitelist is a **validation error**. Expansion is
deliberately controlled to prevent accidental disablement of safety rails.

### `intermediate-pin`

Pin a specific patch version during path computation.

```yaml
- id: pin-ruby-326
  type: intermediate-pin
  ruby: 3.2.6                          # for intermediate Ruby pins
  description: "Stay on 3.2.6 for jemalloc compat"

- id: pin-rails-715
  type: intermediate-pin
  rails: 7.1.5
```

| Field | Required | Type | Default | Notes |
|-------|----------|------|---------|-------|
| `ruby` | one of these required | string | — | `X.Y.Z` patch version. `plan` uses this instead of "latest X.Y." |
| `rails` | one of these required | string | — | `X.Y.Z` patch version. |

Validation:
- Exactly one of `ruby`/`rails` must be set (not both, not neither).
- The pinned version must match the intermediate minor (e.g., `ruby: 3.2.6`
  is valid when the path includes `3.2`; `ruby: 3.1.9` is ignored with a
  warning if `3.1` is not on the path).

## Private gem sources

Any `source` field (on `gem-swap.to[]` or `target-substitute.replacement`)
looks like:

```yaml
source:
  url: https://gems.contribsys.com/
  credentials_env: BUNDLE_GEMS__CONTRIBSYS__COM
```

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `url` | yes | string | Full source URL (including scheme). |
| `credentials_env` | yes | string | Name of the env var Bundler should read for auth. Bundler's convention is `BUNDLE_<HOST>__<DOMAIN>__<TLD>` (underscores separate host parts). |

**Never** store credential values. Only the env var name.

Preflight check (at `audit`/`upgrade` time): verify the env var is set and
non-empty. The value is never logged.

## Authoring prompts (used by `add <type>`)

The `add` subcommand walks the user through each type. These are the
canonical question sequences so that every authoring session produces
consistent YAML.

### `add gem-constraint`

1. Gem name? → `gem`
2. Mode? `[1] require (default)  [2] forbid` → `mode`
3. (if require) Constraint? (e.g., `~> 4.9`, `>= 4.7, < 5.0`) → `constraint`
4. Description? (optional) → `description`

### `add gem-swap`

1. Gem to remove? → `from`
2. Gem(s) to add:
   - Name? Constraint? Private source? (y/N; if y: url, credentials_env)
   - Another? (y/N; loop)
3. Add code transforms to bundle with the swap? (y/N; if y: loop over `add code-transform` subset)
4. When should this fire? `[1] all phases (default)  [2] ruby-phases  [3] rails-phases  [4] specific`
5. Description? → `description`

### `add target-substitute`

1. Which target? `rails` (only v1 option)
2. Replacement gem name? → `replacement.gem`
3. Constraint? → `replacement.constraint`
4. Private gem source? (y/N; if y: url, credentials_env) → `replacement.source`
5. Description? → `description`

### `add code-transform`

1. Pattern (exact string match unless you opt into regex)? → `pattern`
2. Replacement? → `replacement`
3. Regex mode? (y/N) → `mode`
4. Restrict to specific globs? (y/N; if y: comma-separated list) → `files`
5. When should this fire? (same as gem-swap)
6. Description? → `description`

### `add phase-inject`

1. Which phase? `[all | ruby-phases | rails-phases | ruby:X.Y.Z | rails:X.Y | final]` → `phase`
2. Timing? `[1] before  [2] after` → `timing`
3. Command? (single invocation, no pipes) → `action`
4. Promote to its own task row? (y/N) → `as`
5. Description? → `description`

### `add verification-gate`

1. Command? → `command`
2. Apply to which phases? (same as when clause) → `when.phases`
3. Timing? `[1] before built-in gates  [2] after (default)` → `timing`
4. Required? (y/N — required gates block GREEN) → `required`
5. Description? → `description`

### `add policy-override`

1. Which setting? (numbered list from the v1 whitelist) → `setting`
2. Value? (prompt with the setting's type — bool: y/N, int: number, etc.) → `value`
3. Description? → `description`

### `add intermediate-pin`

1. Which language? `[1] ruby  [2] rails` → choose one
2. Patch version? (`X.Y.Z`) → `ruby` or `rails`
3. Description? → `description`
