#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: one-question-gate.sh check < hook.json

Refuses a question prompt that holds more than one question, so the owner is
asked one question at a time.
USAGE
  exit 64
}

[ "${1:-}" = check ] || usage

count=$(jq '.tool_input.questions // [] | length')
[ "$count" -gt 1 ] || exit 0

jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
  --arg text "Ask one question, then wait for the answer before asking the next."
