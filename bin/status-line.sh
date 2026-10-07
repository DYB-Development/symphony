#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: status-line.sh < status.json

The Claude Code status line. On a branch whose name starts with a task issue's
number, it shows the progress of the plan that issue is listed under, exactly as
plan-progress.sh prints it.
USAGE
  exit 64
}

[ $# -eq 0 ] || usage

dir=$(jq -r '.workspace.current_dir // .cwd // empty')
branch=$(git -C "$dir" branch --show-current)
task=${branch%%[!0-9]*}
[ -n "$task" ] || exit 0
repo=$(git -C "$dir" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')

IFS=$'\t' read -r title closed total stage < <("$(dirname "$0")/plan-progress.sh" "$repo" "$task")

filled=$(( closed * 10 / total ))
bar=$(printf '%*s' "$filled" '' | sed 's/ /█/g')$(printf '%*s' $(( 10 - filled )) '' | sed 's/ /░/g')
printf '%s %s %s/%s · %s\n' "$title" "$bar" "$closed" "$total" "$stage"
