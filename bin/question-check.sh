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

cat > /dev/null

jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Rewrite the question in plain words and ask again."}}'
