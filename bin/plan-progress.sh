#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: plan-progress.sh <owner/repo> <task-issue>

Prints one tab-separated line for the plan a task issue is listed under: the
plan's title, its closed units, its total units, and the task's stage from its
`Part of` line. GitHub sub-issues are the only source today; another issue
tracker is added here, behind the same line.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

repo=$1 task=$2

counts=$(gh api "repos/$repo/issues/$task/parent" \
  --jq '[.title, .sub_issues_summary.completed, .sub_issues_summary.total] | @tsv')
stage=$(gh api "repos/$repo/issues/$task" --jq .body \
  | awk '/^## Part of/ { getline; print; exit }' \
  | grep -o 'stage [0-9] of [0-9][^.]*' || true)

printf '%s\t%s\n' "$counts" "$stage"
