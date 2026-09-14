#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: agent-progress.sh record < hook.json

Keeps one progress log per running subagent. `record` is the hook: it appends a
line whenever a subagent marks a step with scribe-step.sh.
USAGE
  exit 64
}

log_dir="${AGENT_PROGRESS_DIR:-$HOME/.claude/agent-progress}"
now="${AGENT_PROGRESS_NOW:-$(date +%s)}"

step_for() {
  local command=$1 marked script
  marked=$(printf '%s' "$command" | sed -nE 's/.*scribe-step\.sh[[:space:]]+"([^"]*)"[[:space:]]+"([^"]*)".*/\1	\2/p')
  if [ -n "$marked" ]; then
    printf '%s' "$marked"
    return
  fi
  script=$(printf '%s' "$command" | sed -nE 's/.*\.claude\/bin\/([A-Za-z0-9_-]+)\.sh.*/\1/p')
  [ -z "$script" ] || printf '\truns %s' "$script"
}

show_progress() {
  awk -F '\t' -v now="$now" '
    function duration(seconds) { return sprintf("%dm%02ds", int(seconds / 60), seconds % 60) }
    NR == 1 { started = $1 }
    $3 != "" { target = " " $3 }
    { type = $2; step = $4; at = $1 }
    END { printf "%s%s — %s — %s on this step, %s in all\n", type, target, step, duration(now - at), duration(now - started) }
  ' "$1"
}

case "${1:-}" in
  record)
    payload=$(cat)
    agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty')
    [ -n "$agent_id" ] || exit 0
    agent_type=$(printf '%s' "$payload" | jq -r '.agent_type // empty')
    if [ "$(printf '%s' "$payload" | jq -r '.hook_event_name // empty')" = SubagentStop ]; then
      step=$(printf '\tfinished')
    else
      step=$(step_for "$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')")
      [ -n "$step" ] || exit 0
    fi
    mkdir -p "$log_dir"
    printf '%s\t%s\t%s\n' "$now" "$agent_type" "$step" >> "$log_dir/$agent_id.log"
    ;;
  "")
    for log in "$log_dir"/*.log; do
      [ -f "$log" ] || continue
      show_progress "$log"
    done
    ;;
  *) usage ;;
esac
