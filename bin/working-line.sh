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
  local payload fields session="" agent_id="" event="" description=""
  payload=$(cat)
  fields=$(printf '%s' "$payload" | jq -r '
    def text: (. // "") | tostring | sub("\n+\\z"; "");
    @sh "session=\(.session_id | text) agent_id=\(.agent_id | text) event=\(.hook_event_name | text)",
    @sh "description=\(.tool_input.description // .tool_name | text)"')
  eval "$fields"
  [ -n "$session" ] || return 0
  [ -z "$agent_id" ] || return 0
  if [ "$event" = Stop ]; then
    rm -f "$record_dir/$session"
    return 0
  fi
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
