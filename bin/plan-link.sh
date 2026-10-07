#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: plan-link.sh <owner/repo> <plan-issue> <task-issue>

Lists a task issue under its plan issue as a GitHub sub-issue, so the plan's
progress can be counted from the plan alone.
See ~/.claude/rules/feature-plan.md.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage

repo=$1 plan=$2 task=$3

id=$(gh api "repos/$repo/issues/$task" --jq .id)
gh api -X POST "repos/$repo/issues/$plan/sub_issues" -F "sub_issue_id=$id" >/dev/null
