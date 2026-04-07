#!/usr/bin/env bash
# Capture Rails deprecation warnings from the test suite.
# Usage: bash capture-deprecations.sh [rspec|minitest]
# Output: prints grouped/counted deprecation warnings to stdout

set -euo pipefail

FRAMEWORK="${1:-auto}"
OUTPUT_FILE="/tmp/rails-deprecations-$$.txt"

# Auto-detect test framework
if [[ "$FRAMEWORK" == "auto" ]]; then
  if [[ -f "spec/spec_helper.rb" ]] || [[ -f ".rspec" ]]; then
    FRAMEWORK="rspec"
  else
    FRAMEWORK="minitest"
  fi
fi

echo "==> Detecting test framework: $FRAMEWORK"
echo "==> Running test suite to capture deprecation warnings..."
echo ""

if [[ "$FRAMEWORK" == "rspec" ]]; then
  RAILS_ENV=test bundle exec rspec --no-color 2>&1 | \
    grep -E "DEPRECATION WARNING|is deprecated|will be removed|deprecated" | \
    sort | uniq -c | sort -rn > "$OUTPUT_FILE" || true
else
  RAILS_ENV=test bundle exec rails test 2>&1 | \
    grep -E "DEPRECATION WARNING|is deprecated|will be removed|deprecated" | \
    sort | uniq -c | sort -rn > "$OUTPUT_FILE" || true
fi

# Also capture boot-time deprecations
echo "" >> "$OUTPUT_FILE"
echo "--- Boot-time deprecations ---" >> "$OUTPUT_FILE"
RAILS_ENV=development bundle exec rails runner "puts 'OK'" 2>&1 | \
  grep -E "DEPRECATION WARNING|is deprecated|will be removed|deprecated" | \
  sort | uniq -c | sort -rn >> "$OUTPUT_FILE" || true

TOTAL=$(grep -c "." "$OUTPUT_FILE" 2>/dev/null || echo 0)

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No deprecation warnings found."
else
  echo "==> Found deprecation warnings:"
  echo ""
  cat "$OUTPUT_FILE"
  echo ""
  echo "==> Total unique warning lines: $TOTAL"
  echo "==> Saved to: $OUTPUT_FILE"
fi
