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

cache_dir="${STATUS_LINE_DIR:-$HOME/.claude/status-line}"
now="${STATUS_LINE_NOW:-$(date +%s)}"

read_progress() {
  local cache
  cache="$cache_dir/$(printf '%s %s' "$repo" "$branch" | shasum | cut -c1-40)"
  if [ -f "$cache" ] && [ $(( now - $(head -1 "$cache") )) -lt 60 ]; then
    sed -n 2p "$cache"
    return
  fi
  local progress
  progress=$("$(dirname "$0")/plan-progress.sh" "$repo" "$task" 2>/dev/null) || progress=""
  mkdir -p "$cache_dir"
  printf '%s\n%s\n' "$now" "$progress" > "$cache"
  printf '%s\n' "$progress"
}

plan_part() {
  [ -n "$task" ] || return 0
  repo=$(git -C "$dir" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
  local progress title closed total stage filled bar
  progress=$(read_progress)
  [ -n "$progress" ] || return 0
  IFS=$'\t' read -r title closed total stage <<< "$progress"
  filled=$(( closed * 10 / total ))
  bar=$(printf '%*s' "$filled" '' | sed 's/ /█/g')$(printf '%*s' $(( 10 - filled )) '' | sed 's/ /░/g')
  printf '%s · %s\n%s %s/%s\n' "$title" "$stage" "$bar" "$closed" "$total"
}

working_part() {
  [ -n "$session" ] || return 0
  "$(dirname "$0")/working-line.sh" show "$session"
}

flag_part() {
  [ -n "$session" ] || return 0
  "$(dirname "$0")/owner-turn.sh" flags "$session"
}

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // empty')
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
branch=$(git -C "$dir" branch --show-current)
task=${branch%%[!0-9]*}

printf '%s\n%s\n%s\n' "$(working_part)" "$(flag_part)" "$(plan_part)" | awk 'NF'
