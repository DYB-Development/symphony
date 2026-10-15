#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: agent-model.sh set < hook.json
       agent-model.sh lookup <name> <fallback>

set     Gives a spawned agent the model the owner's agent models file names
        for it.
lookup  Prints the model the file names for <name>, or <fallback> when it
        names none.
USAGE
  exit 64
}

models="${SYMPHONY_AGENT_MODELS_FILE:-$HOME/.config/symphony/agent-models.json}"

model_for() {
  [ -r "$models" ] || return 0
  jq -r --arg name "$1" '.[$name] | select(. == "haiku" or . == "sonnet" or . == "opus") // ""' "$models" 2>/dev/null || true
}

set_model() {
  local input named name model
  input="$(cat)"
  { read -r named; read -r name; } < <(printf '%s' "$input" | jq -r '(.tool_input.model // ""), (.tool_input.subagent_type // "")')
  [ -z "$named" ] || return 0
  model="$(model_for "$name")"
  [ -n "$model" ] || return 0

  printf '%s' "$input" | jq -c --arg model "$model" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: (.tool_input + {model: $model})}}'
}

lookup() {
  local model
  model="$(model_for "$1")"
  printf '%s\n' "$model"
}

case "${1:-}" in
  set) set_model ;;
  lookup) [ $# -eq 3 ] || usage; lookup "$2" "$3" ;;
  *) usage ;;
esac
