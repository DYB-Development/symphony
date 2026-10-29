#!/usr/bin/env bash
set -euo pipefail

answers_dir=${SYMPHONY_ANSWERS_DIR:-"$(cd "$(dirname "$0")/.." && pwd)/rules/answers"}
repo_answers_dir=${SYMPHONY_REPO_ANSWERS_DIR:-"$HOME/.config/symphony/answers"}

settles=false
if [ "${1:-}" = --settles ]; then
  settles=true
  shift
fi

repo=""
if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  repo=$(basename "$(dirname "$common")")
fi

common_words='a an and are as at be by can do does for from has have how i if in is it its me my of on or our should so that the their them then there these this to was we what when where which who why will with would you your'

entries() {
  local label="$1" file="$2"
  [ -n "$label" ] && [ -f "$file" ] || { echo '[]'; return; }
  jq -c --arg label "$label" '[.answers[] | . + {label: $label}]' "$file"
}

matches=$(jq -rn --arg search "$*" --arg common "$common_words" --argjson settles "$settles" \
  --argjson repo "$(entries "$repo" "$repo_answers_dir/$repo.json")" \
  --argjson defaults "$(entries default "$answers_dir/defaults.json")" '
  def words: ascii_downcase | [scan("[[:alnum:]]+")] - ($common | split(" "));
  ($search | words | unique) as $words |
  (if $settles then (($words | length) + 1) / 2 | floor else 1 end) as $needed |
  ($repo | map(.name)) as $replaced |
  [($repo + ($defaults | map(select(.name as $name | $replaced | index($name) | not))))[]
   | . + {shared: ((.question | words) - ((.question | words) - $words) | unique | length)}
   | select(.shared > 0 and .shared >= $needed)]
  | sort_by(.label == "default", -.shared)
  | .[:5]
  | map("\(.label): \(.question)\n\(.answer)")
  | join("\n\n")
')

[ -n "$matches" ] || exit 1
printf '%s\n' "$matches"
