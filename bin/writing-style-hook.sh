#!/usr/bin/env bash
set -uo pipefail

here="$(dirname "$0")"
rules_file="${CLAUDE_WRITING_STYLE_FILE:-$here/../rules/writing-style.md}"
phrases_file="${CLAUDE_BANNED_PHRASES_FILE:-$here/../rules/banned-phrases.txt}"
[ -f "$rules_file" ] || exit 0

# Read from this script's own location, not from the writing style file, which
# can be pointed at a voice file kept anywhere.
rules_dir="$(cd -P "$here/../rules" 2>/dev/null && pwd)" || rules_dir=""

context=""
if [ -n "$rules_dir" ]; then
  context="Every rules file this system follows is in $rules_dir. Read one from"
  context+=$' there when you are told to read it by name.\n\n'
fi
context+="$(cat "$rules_file")"
if [ -f "$phrases_file" ]; then
  context+=$'\n\n## Banned phrases\n\nNever write any of these:\n\n'
  context+="$(grep -v '^[[:space:]]*#' "$phrases_file" | grep -v '^[[:space:]]*$' | sed 's/^/- /')"
fi

payload="$(cat)"
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty')"

jq -nc --arg event "$event" --arg rules "$context" \
  '{hookSpecificOutput: {hookEventName: $event, additionalContext: $rules}}'
