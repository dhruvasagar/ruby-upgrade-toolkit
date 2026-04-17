# Verification Suite

Canonical bash for checking project health during an upgrade. The `audit`, `plan`, `fix`, `status`, and `upgrade` skills all use the commands below so drift between them is impossible.

Each skill loads this file when it needs the canonical form; small inline snippets (e.g. a single `ruby -v`) remain inline for speed.

## Test suite — full run

```bash
if [[ -d "spec" ]]; then
  bundle exec rspec --no-color --format progress 2>&1 | tail -15
else
  bundle exec rails test 2>&1 | tail -10 2>/dev/null || echo "No test suite found"
fi
```

## Test suite — failure count (for baselines and phase gates)

```bash
BASELINE_FAILURES=$(bundle exec rspec --no-color --format progress 2>&1 \
  | grep -oE "[0-9]+ failure" | grep -oE "[0-9]+" | head -1)
echo "Failures: ${BASELINE_FAILURES:-0}"
```

Use this to record a pre-upgrade baseline. In later phases, only failures **above** this baseline are upgrade-introduced regressions. Pre-existing failures are documented separately and not auto-fixed.

## Deprecation warnings

```bash
if [[ -d "spec" ]]; then
  DEPR=$(RAILS_ENV=test bundle exec rspec --no-color 2>&1 | grep -c "DEPRECATION" || true)
else
  DEPR=$(RAILS_ENV=test bundle exec rails test 2>&1 | grep -c "DEPRECATION" || true)
fi
echo "Deprecation warnings: $DEPR"
```

For dynamic deprecation capture (top patterns by count):

```bash
RAILS_ENV=test bundle exec rspec --no-color 2>&1 \
  | grep -E "DEPRECATION|deprecated" | sort | uniq -c | sort -rn | head -30
```

## Ruby warnings

```bash
RUBY_WARN=$(RUBYOPT="-W:deprecated" bundle exec ruby -e "require 'bundler/setup'" 2>&1 \
  | grep -c "warning:" || echo 0)
echo "Ruby warnings: $RUBY_WARN"
```

## RuboCop — offense count (JSON)

```bash
bundle exec rubocop --parallel --format json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
offenses = sum(len(f['offenses']) for f in data.get('files', []))
print(f'RuboCop offenses: {offenses}')
" 2>/dev/null || bundle exec rubocop --parallel 2>&1 | tail -3
```

## RuboCop — auto-correct loop

```bash
bundle exec rubocop -a 2>&1 | tail -10     # safe auto-corrections
bundle exec rubocop -A 2>&1 | tail -10     # unsafe auto-corrections (review before accepting)
```

## Zeitwerk (Rails only)

```bash
if [[ -f "config/application.rb" ]]; then
  bundle exec rails zeitwerk:check 2>&1 | head -20
fi
```

## Outdated gems signal

```bash
bundle outdated 2>/dev/null | head -30
```

## Readiness tiers

Skills that verify a phase or produce a dashboard categorise the result as:

| Tier   | Meaning |
|--------|---------|
| GREEN  | Tests passing (only pre-existing failures, if any); 0 RuboCop offenses; 0 deprecation warnings |
| YELLOW | Tests passing but RuboCop offenses or deprecation warnings remain |
| RED    | New test failures present (above the pre-existing baseline) — do not proceed |

RED is the only tier that blocks phase progression. YELLOW is logged and reported in the final summary; GREEN unlocks the next phase.
