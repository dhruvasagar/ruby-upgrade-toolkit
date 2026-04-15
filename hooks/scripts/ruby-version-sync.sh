#!/usr/bin/env bash
# PostToolUse hook: Validate .ruby-version and Gemfile ruby directive stay in sync.
# Fires when either .ruby-version or Gemfile is edited.
# Non-blocking — emits a warning but does not prevent the write.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -z "$file_path" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
normalized="${file_path#"$project_dir/"}"

# Only fire on .ruby-version or Gemfile
if [[ "$normalized" != ".ruby-version" ]] && [[ "$normalized" != "Gemfile" ]]; then
  exit 0
fi

ruby_version_file="$project_dir/.ruby-version"
gemfile="$project_dir/Gemfile"

# Read .ruby-version (strip whitespace)
if [[ ! -f "$ruby_version_file" ]]; then
  exit 0
fi
rv_version=$(cat "$ruby_version_file" | tr -d '[:space:]')

# Read Gemfile ruby directive
if [[ ! -f "$gemfile" ]]; then
  exit 0
fi
gemfile_version=$(grep -E "^ruby ['\"]" "$gemfile" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?" | head -1)

if [[ -z "$gemfile_version" ]]; then
  # No ruby directive in Gemfile — not an error, just no check possible
  exit 0
fi

# Compare major.minor (patch may legitimately differ between .ruby-version and Gemfile ~> pin)
rv_minor=$(echo "$rv_version" | cut -d. -f1-2)
gf_minor=$(echo "$gemfile_version" | cut -d. -f1-2)

if [[ "$rv_minor" != "$gf_minor" ]]; then
  echo "WARNING: Ruby version mismatch detected:"
  echo "  .ruby-version: $rv_version (minor: $rv_minor)"
  echo "  Gemfile ruby:  $gemfile_version (minor: $gf_minor)"
  echo "  Run: /ruby-upgrade-toolkit:fix ruby:$rv_version to reconcile"
fi

exit 0
