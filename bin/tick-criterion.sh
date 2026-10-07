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

printf '%s\n' "$body" | awk -v want="$position" '
  /^## / { inside = ($0 == "## Acceptance criteria") }
  inside && /^- \[[ x]\] / { seen++; if (seen == want) sub(/^- \[ \]/, "- [x]") }
  { print }
' | gh api -X PATCH "repos/$repo/issues/$issue" -F body=@- >/dev/null
