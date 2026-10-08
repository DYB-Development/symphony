#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: plan-progress.sh <owner/repo> <task-issue>

Prints one tab-separated line for the plan a task issue is listed under: the
plan's title, its closed units, its total units, the task's stage from its
`Part of` line, and each stage's closed units out of its units, in stage order,
as `<stage>:<closed>/<total>` separated by spaces. GitHub sub-issues are the only source today; another issue
tracker is added here, behind the same line.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

repo=$1 task=$2

if ! parent=$(gh api "repos/$repo/issues/$task/parent" \
  --jq '[.number, .title, .sub_issues_summary.completed, .sub_issues_summary.total] | @tsv' 2>&1); then
  case "$parent" in *"HTTP 404"*) exit 1 ;; *) exit 69 ;; esac
fi
plan=${parent%%$'\t'*}
counts=${parent#*$'\t'}
body=$(gh api "repos/$repo/issues/$task" --jq .body) || exit 69
stage=$(printf '%s\n' "$body" \
  | awk '/^## Part of/ { getline; print; exit }' \
  | grep -o 'stage [0-9] of [0-9][^.]*' || true)
criteria=$(printf '%s\n' "$body" | awk '
  /^## / { inside = ($0 == "## Acceptance criteria") }
  inside && /^- \[x\] / { ticked++ }
  inside && /^- \[[ x]\] / { total++ }
  END { printf "%d/%d", ticked, total }
')

units=$(gh api "repos/$repo/issues/$plan/sub_issues" --paginate) || exit 69
stages=$(printf '%s' "$units" \
  | jq -r '.[] | [(.body // "" | capture("## Part of\\s*\\n[^\\n]*stage (?<n>[0-9]+) of").n), .state] | @tsv' \
  | awk -F'\t' '{ total[$1]++; if ($2 == "closed") closed[$1]++ }
      END { for (n in total) printf "%d:%d/%d\n", n, closed[n], total[n] }' \
  | sort -n | paste -sd' ' -)

printf '%s\t%s\t%s\t%s\n' "$counts" "$stage" "$stages" "$criteria"
