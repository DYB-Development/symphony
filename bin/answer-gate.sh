#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: answer-gate.sh check < hook.json

Refuses a question the owner has already answered, handing the session the
approved repo answer or default that settles it.
See ~/.claude/rules/saved-answers.md.
USAGE
  exit 64
}

[ "${1:-}" = check ] || usage

payload=$(cat)
[ "$(printf '%s' "$payload" | jq '.tool_input.questions // [] | length')" -eq 1 ] || exit 0
cd "$(printf '%s' "$payload" | jq -r '.cwd // "."')"
question=$(printf '%s' "$payload" | jq -r '.tool_input.questions[0].question')

saved=$("$(dirname "$0")/saved-answers.sh" --settles "$question") || exit 0

jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
  --arg text "The owner has already answered this question. Use the saved answer below instead of asking.

$saved

If this saved answer does not fit, rephrase the question to say why it differs."
