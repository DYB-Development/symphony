#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pattern-scan.sh <owner/repo> <pr-number> <draft.json>

Matches every line a pull request adds against the patterns in the packs under
rules/patterns, and writes each hit beside the review draft.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage

repo=$1
pr=$2
draft=$3

packs_dir=${SYMPHONY_PATTERNS_DIR:-"$(cd "$(dirname "$0")/.." && pwd)/rules/patterns"}
result="${draft%.json}.scan.json"

diff=$(gh pr diff "$pr" --repo "$repo")

added=$(printf '%s\n' "$diff" | awk '
  /^diff --git / { in_hunk = 0; next }
  !in_hunk && /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
  /^@@ / { split($3, n, ","); line = n[1] + 0; if (line < 0) line = -line; in_hunk = 1; next }
  !in_hunk { next }
  /^\\/ { next }
  /^-/ { next }
  /^\+/ { print path "\t" line "\t" substr($0, 2); line++; next }
  { line++ }
')

hits='[]'
while IFS=$'\037' read -r name check regex; do
  matches=$(printf '%s\n' "$added" | cut -f3- | grep -n -E -e "$regex" | cut -d: -f1 || true)
  for index in $matches; do
    row=$(printf '%s\n' "$added" | sed -n "${index}p")
    hits=$(jq -c --arg path "$(printf '%s' "$row" | cut -f1)" --argjson line "$(printf '%s' "$row" | cut -f2)" \
      --arg pattern "$name" --arg check "$check" \
      '. + [{path: $path, line: $line, pattern: $pattern, check: $check}]' <<<"$hits")
  done
done < <(jq -r '.patterns[] | [.name, .check, .regex] | join("\u001f")' "$packs_dir"/*.json)

jq -n --argjson hits "$hits" '{hits: $hits}' > "$result"
