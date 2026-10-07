#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: working-line.sh record < hook.json
       working-line.sh show <session>

Keeps the line the status line shows while a session works. `record` is the
hook: it keeps the description of the session's most recent tool call. `show`
prints that line for one session.
USAGE
  exit 64
}

record_dir="${WORKING_LINE_DIR:-$HOME/.claude/working-line}"

record() {
  local payload session description
  payload=$(cat)
  session=$(printf '%s' "$payload" | jq -r '.session_id // empty')
  [ -n "$session" ] || return 0
  description=$(printf '%s' "$payload" | jq -r '.tool_input.description // .tool_name // empty')
  mkdir -p "$record_dir"
  printf '%s\n' "$description" > "$record_dir/$session"
}

show() {
  [ -f "$record_dir/$1" ] || return 0
  printf '● working · %s\n' "$(cat "$record_dir/$1")"
}

case "${1:-}" in
  record) [ $# -eq 1 ] || usage; record ;;
  show) [ $# -eq 2 ] || usage; show "$2" ;;
  *) usage ;;
esac
