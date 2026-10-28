#!/usr/bin/env bash
set -euo pipefail

answers_dir=${SYMPHONY_ANSWERS_DIR:-"$(cd "$(dirname "$0")/.." && pwd)/rules/answers"}
repo_answers_dir=${SYMPHONY_REPO_ANSWERS_DIR:-"$HOME/.config/symphony/answers"}

repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")

words=$(printf '%s\n' "$*" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | jq -R . | jq -sc 'map(select(length > 0))')

entries() {
  local label="$1" file="$2"
  [ -f "$file" ] || { echo '[]'; return; }
  jq -c --arg label "$label" '[.answers[] | . + {label: $label}]' "$file"
}

matches=$(jq -rn --argjson words "$words" \
  --argjson repo "$(entries "$repo" "$repo_answers_dir/$repo.json")" \
  --argjson defaults "$(entries default "$answers_dir/defaults.json")" '
  def words: ascii_downcase | [scan("[[:alnum:]]+")];
  [($repo + $defaults)[]
   | select((.question | words) - ((.question | words) - $words) | length > 0)
   | "\(.label): \(.question)\n\(.answer)"]
  | join("\n\n")
')

[ -n "$matches" ] || exit 1
printf '%s\n' "$matches"
