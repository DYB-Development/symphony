#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: description-gate.sh check < hook.json

Refuses a shell command that carries no description, so the owner always reads
what a command does in plain words rather than the command itself.
See ~/.claude/rules/writing-style.md.
USAGE
  exit 64
}

[ "${1:-}" = check ] || usage

description=$(jq -r '.tool_input.description // empty')
[ -z "$description" ] || exit 0

jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}}'
