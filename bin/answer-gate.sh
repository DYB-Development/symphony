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

here="$(cd "$(dirname "$0")" && pwd)"
payload=$(cat)
[ "$(printf '%s' "$payload" | jq '.tool_input.questions // [] | length')" -eq 1 ] || exit 0
cd "$(printf '%s' "$payload" | jq -r '.cwd // "."')"
question=$(printf '%s' "$payload" | jq -r '.tool_input.questions[0].question')

status=0
saved=$("$here/saved-answers.sh" --settles "$question" 2>/dev/null) || status=$?
[ "$status" -eq 1 ] && exit 0
if [ "$status" -ne 0 ]; then
  echo "answer-gate.sh: the saved answers search failed, so the question was asked unchecked" >&2
  exit 0
fi

jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
  --arg text "The owner has already answered this question. Use the saved answer below instead of asking.

$saved

If this saved answer does not fit, rephrase the question to say why it differs."
