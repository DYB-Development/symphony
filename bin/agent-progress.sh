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

case "${1:-}" in
  record)
    payload=$(cat)
    agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty')
    [ -n "$agent_id" ] || exit 0
    agent_type=$(printf '%s' "$payload" | jq -r '.agent_type // empty')
    command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    step=$(printf '%s' "$command" | sed -nE 's/.*scribe-step\.sh[[:space:]]+"([^"]*)"[[:space:]]+"([^"]*)".*/\1	\2/p')
    if [ -z "$step" ]; then
      script=$(printf '%s' "$command" | sed -nE 's/.*\.claude\/bin\/([A-Za-z0-9_-]+)\.sh.*/\1/p')
      [ -n "$script" ] || exit 0
      step=$(printf '\truns %s' "$script")
    fi
    mkdir -p "$log_dir"
    printf '%s\t%s\t%s\n' "$now" "$agent_type" "$step" >> "$log_dir/$agent_id.log"
    ;;
  *) usage ;;
esac
