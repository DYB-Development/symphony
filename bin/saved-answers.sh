#!/usr/bin/env bash
set -euo pipefail

answers_dir=${SYMPHONY_ANSWERS_DIR:-"$(cd "$(dirname "$0")/.." && pwd)/rules/answers"}
repo_answers_dir=${SYMPHONY_REPO_ANSWERS_DIR:-"$HOME/.config/symphony/answers"}

repo=""
if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  repo=$(basename "$(dirname "$common")")
fi

words=$(printf '%s\n' "$*" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | jq -R . | jq -sc 'map(select(length > 0))')

entries() {
  local label="$1" file="$2"
  [ -n "$label" ] && [ -f "$file" ] || { echo '[]'; return; }
  jq -c --arg label "$label" '[.answers[] | . + {label: $label}]' "$file"
}

matches=$(jq -rn --argjson words "$words" \
  --argjson repo "$(entries "$repo" "$repo_answers_dir/$repo.json")" \
  --argjson defaults "$(entries default "$answers_dir/defaults.json")" '
  def words: ascii_downcase | [scan("[[:alnum:]]+")];
  ($repo | map(.name)) as $replaced |
  [($repo + ($defaults | map(select(.name as $name | $replaced | index($name) | not))))[]
   | select((.question | words) - ((.question | words) - $words) | length > 0)
   | "\(.label): \(.question)\n\(.answer)"]
  | join("\n\n")
')

[ -n "$matches" ] || exit 1
printf '%s\n' "$matches"
