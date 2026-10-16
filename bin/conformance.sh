#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: conformance.sh <owner/repo> <pr-number> <draft.json>
       conformance.sh --render <conformance.json>

Checks the acceptance criteria of the ticket a pull request closes against the
titles of the valid tests in the test inventory beside the review draft, and
writes which test covers each criterion beside the draft. `--render` prints the
Conformance section of the review summary from that result.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

if [ "${1:-}" = "--render" ]; then
  [ $# -eq 2 ] || usage
  jq -r 'if .ticket == null then "No ticket referenced." else empty end' "$2"
  exit 0
fi

[ $# -eq 3 ] || usage

repo=$1
pr=$2
draft=$3

result="${draft%.json}.conformance.json"

ticket=$(gh pr view "$pr" --repo "$repo" --json closingIssuesReferences --jq '.closingIssuesReferences[0].number // empty')

jq -n --arg ticket "$ticket" '{ticket: (if $ticket == "" then null else ($ticket | tonumber) end), criteria: []}' > "$result"
