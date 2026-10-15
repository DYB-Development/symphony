#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: agent-model.sh set < hook.json

Gives a spawned agent the model the owner's agent models file names for it.
USAGE
  exit 64
}

[ "${1:-}" = set ] || usage

models="${SYMPHONY_AGENT_MODELS_FILE:-$HOME/.config/symphony/agent-models.json}"
[ -r "$models" ] || exit 0
input="$(cat)"
{ read -r named; read -r name; } < <(printf '%s' "$input" | jq -r '(.tool_input.model // ""), (.tool_input.subagent_type // "")')
[ -z "$named" ] || exit 0
model="$(jq -r --arg name "$name" '.[$name] // ""' "$models" 2>/dev/null)" || exit 0
[ -n "$model" ] || exit 0

printf '%s' "$input" | jq -c --arg model "$model" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: (.tool_input + {model: $model})}}'
