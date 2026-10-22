#!/usr/bin/env bash
set -uo pipefail

payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
cwd="${cwd:-$PWD}"

lessons_dir="${SYMPHONY_LESSONS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lessons}"

top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
lessons_file="$lessons_dir/$(basename "$top").md"
[ -f "$lessons_file" ] || exit 0

jq -nc --arg context "$(cat "$lessons_file")" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
