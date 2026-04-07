#!/usr/bin/env bash
# PostToolUse hook: Log any changes to db/migrate/ files.
# Creates an upgrade_audit.log in the project root for traceability.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only log migration file changes
if [[ -z "$file_path" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
normalized="${file_path#"$project_dir/"}"

if [[ "$normalized" != db/migrate/* ]]; then
  exit 0
fi

# Determine the operation type
tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null)

# Append to audit log
log_file="$project_dir/upgrade_audit.log"
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
migration_name=$(basename "$file_path")

echo "[$timestamp] $tool_name: $migration_name" >> "$log_file"

echo "Logged migration change: $migration_name → upgrade_audit.log"
exit 0
