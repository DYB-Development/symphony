#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: tick-criterion.sh <owner/repo> <issue> <position>

Ticks one acceptance criterion on a task issue, counting from 1 down the boxes
under its "## Acceptance criteria" heading. Every other line of the body is
left as it is. Run it for each criterion a commit covers, once that commit
lands.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage

repo=$1 issue=$2 position=$3

body=$(gh api "repos/$repo/issues/$issue" --jq .body)

count=$(printf '%s\n' "$body" | awk '
  /^## / { inside = ($0 == "## Acceptance criteria") }
  inside && /^- \[[ x]\] / { seen++ }
  END { print seen + 0 }
')
if [ "$position" -gt "$count" ]; then
  printf 'tick-criterion.sh: #%s has %s acceptance criteria, so there is no criterion %s\n' "$issue" "$count" "$position" >&2
  exit 1
fi

ticked=$(printf '%s\n' "$body" | awk -v want="$position" '
  /^## / { inside = ($0 == "## Acceptance criteria") }
  inside && /^- \[[ x]\] / { seen++; if (seen == want) sub(/^- \[ \]/, "- [x]") }
  { print }
')

if [ "$ticked" = "$body" ]; then
  printf 'Criterion %s on #%s is already ticked\n' "$position" "$issue"
  exit 0
fi

printf '%s\n' "$ticked" | gh api -X PATCH "repos/$repo/issues/$issue" -F body=@- >/dev/null
