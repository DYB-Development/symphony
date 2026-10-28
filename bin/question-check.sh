#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: question-check.sh check < hook.json

Hands a question prompt to the draft reader and refuses it when the reader
could not follow it on one read, so the owner is asked in plain words.
See ~/.claude/rules/draft-reading.md.
USAGE
  exit 64
}

[ "${1:-}" = check ] || usage

here="$(dirname "$0")"
run="$(mktemp -d "${TMPDIR:-/tmp}/question-check.XXXXXX")"
trap 'rm -rf "$run"' EXIT

jq -r '.tool_input.questions[].question' > "$run/question.md"

status=0
"$here/read-draft.sh" "$run/question.md" > /dev/null 2>&1 || status=$?
[ "$status" -eq 0 ] && exit 0
if [ "$status" -ne 1 ]; then
  echo "question-check.sh: the draft reader failed, so the question was asked unchecked" >&2
  exit 0
fi

jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Rewrite the question in plain words and ask again."}}'
