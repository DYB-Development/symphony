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
  jq -r 'if .ticket == null then "No ticket referenced."
    else .criteria[] | if (.covered_by | length) > 0
      then "- [x] \(.text) Covered by \(.covered_by | map("\"\(.)\"") | join(", "))."
      else empty end
    end' "$2"
  exit 0
fi

[ $# -eq 3 ] || usage

repo=$1
pr=$2
draft=$3

result="${draft%.json}.conformance.json"

inventory="${draft%.json}.tests.json"

ticket=$(gh pr view "$pr" --repo "$repo" --json closingIssuesReferences --jq '.closingIssuesReferences[0].number // empty')

if [ -z "$ticket" ]; then
  jq -n '{ticket: null, criteria: []}' > "$result"
  exit 0
fi

criteria=$(gh issue view "$ticket" --repo "$repo" --json body --jq '.body' | awk '
  /^## Acceptance criteria/ { on = 1; next }
  /^## / { on = 0 }
  on && /^- \[[ xX]\] / { sub(/^- \[[ xX]\] /, ""); print }
')
titles=$(jq -r '.tests[].title' "$inventory")

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model="$("$root/bin/agent-model.sh" lookup conformance sonnet)"

question='You are shown the acceptance criteria of a ticket and the titles of the tests a pull request adds. Decide which titles cover which criterion. A title covers a criterion when the behaviour it names is the behaviour the criterion asks for.

Reply with one line per criterion and nothing else, giving the criterion number and the numbers of the titles that cover it, or none:
1: 2, 3
2: none'

reply=$({
  printf 'The acceptance criteria:\n\n'
  printf '%s\n' "$criteria" | awk '{ print NR ". " $0 }'
  printf '\nThe test titles:\n\n'
  printf '%s\n' "$titles" | awk 'NF { print NR ". " $0 }'
} | claude -p --model "$model" --system-prompt "$question" --tools "" --setting-sources "" \
    --no-session-persistence --strict-mcp-config) ||
  { echo "conformance.sh: the question about the criteria failed" >&2; exit 70; }

jq -n --argjson ticket "$ticket" --arg criteria "$criteria" --arg titles "$titles" --arg reply "$reply" '
  ($titles | split("\n") | map(select(length > 0))) as $titles
  | ($reply | split("\n") | map(capture("^(?<n>[0-9]+): *(?<covers>.*)$")?)
      | map({key: .n, value: (.covers | [scan("[0-9]+") | tonumber]) }) | from_entries) as $covers
  | {ticket: $ticket, criteria: ($criteria | split("\n") | map(select(length > 0)) | to_entries
      | map({text: .value, covered_by: [($covers["\(.key + 1)"] // [])[] | $titles[. - 1] | select(. != null)]}))}' > "$result"
