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

parent=$(gh api "repos/$repo/issues/$task/parent" \
  --jq '[.number, .title, .sub_issues_summary.completed, .sub_issues_summary.total] | @tsv')
plan=${parent%%$'\t'*}
counts=${parent#*$'\t'}
stage=$(gh api "repos/$repo/issues/$task" --jq .body \
  | awk '/^## Part of/ { getline; print; exit }' \
  | grep -o 'stage [0-9] of [0-9][^.]*' || true)

stages=$(gh api "repos/$repo/issues/$plan/sub_issues" --paginate \
  | jq -r '.[] | [(.body // "" | capture("stage (?<n>[0-9]+) of").n), .state] | @tsv' \
  | awk -F'\t' '{ total[$1]++; if ($2 == "closed") closed[$1]++ }
      END { for (n in total) printf "%d:%d/%d\n", n, closed[n], total[n] }' \
  | sort -n | paste -sd' ' -)

printf '%s\t%s\t%s\n' "$counts" "$stage" "$stages"
