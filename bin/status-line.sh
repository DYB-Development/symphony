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

within_seconds() {
  perl -MTime::HiRes=ualarm -e '
    my $limit = shift;
    my $pid = fork;
    if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$pid; exit 69 };
    ualarm($limit * 1_000_000);
    waitpid $pid, 0;
    exit($? >> 8);
  ' "$@"
}

read_progress() {
  local cache progress code=0 previous=""
  cache="$cache_dir/$(printf '%s %s' "$repo" "$branch" | shasum | cut -c1-40)"
  if [ -f "$cache" ] && [ $(( now - $(head -1 "$cache") )) -lt 60 ]; then
    sed -n '2,3p' "$cache"
    return
  fi
  [ -f "$cache" ] && previous=$(sed -n 2p "$cache")
  progress=$(within_seconds "${STATUS_LINE_LIMIT:-1.5}" "$(dirname "$0")/plan-progress.sh" "$repo" "$task" 2>/dev/null) || code=$?
  local state=fresh
  if [ "$code" -eq 69 ]; then
    progress=$previous
    state=stale
  elif [ "$code" -ne 0 ]; then
    progress=""
  fi
  mkdir -p "$cache_dir"
  printf '%s\n%s\n%s\n' "$now" "$progress" "$state" > "$cache"
  printf '%s\n%s\n' "$progress" "$state"
}

stage_square() {
  if [ "${1%/*}" = "${1#*/}" ]; then
    printf '\033[32m■\033[0m'
  elif [ "${1%/*}" -gt 0 ]; then
    printf '\033[33m■\033[0m'
  else
    printf '\033[90m■\033[0m'
  fi
}

plan_part() {
  [ -n "$task" ] || return 0
  repo=$(git -C "$dir" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
  local progress title closed total stage stages criteria counts squares=""
  local read state
  read=$(read_progress)
  progress=$(printf '%s\n' "$read" | sed -n 1p)
  state=$(printf '%s\n' "$read" | sed -n 2p)
  if [ -z "$progress" ]; then
    [ "$state" != stale ] || printf 'Plan progress unavailable: GitHub cannot be read\n'
    return 0
  fi
  IFS=$'\t' read -r title closed total stage stages criteria <<< "$progress"
  for counts in $stages; do
    squares+=$(stage_square "${counts#*:}")
  done
  printf '%s · %s\n%s %s/%s%s\n' "$title" "$stage" "$squares" "$closed" "$total" "$([ "$state" = stale ] && printf ' · out of date')"
  criteria_bar "${criteria:-0/0}"
}

criteria_bar() {
  local ticked=${1%/*} all=${1#*/} filled
  [ "$all" -gt 0 ] || return 0
  filled=$(( ticked * 10 / all ))
  printf '%s%s %s/%s criteria\n' \
    "$(printf '%*s' "$filled" '' | sed 's/ /█/g')" \
    "$(printf '%*s' $(( 10 - filled )) '' | sed 's/ /░/g')" "$ticked" "$all"
}

working_part() {
  [ -n "$session" ] || return 0
  "$(dirname "$0")/working-line.sh" show "$session"
}

agents_part() {
  [ -n "$session" ] || return 0
  "$(dirname "$0")/agent-progress.sh" line "$session"
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

printf '%s\n%s\n%s\n%s\n' "$(working_part)" "$(agents_part)" "$(flag_part)" "$(plan_part)" | awk 'NF'
