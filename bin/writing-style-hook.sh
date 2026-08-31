#!/usr/bin/env bash
set -uo pipefail

here="$(dirname "$0")"

# A file of the same name in the overlay replaces the one this package ships, so
# nothing here has to be edited to change a rule and no update overwrites one.
overlay_dir="${SYMPHONY_OVERLAY_DIR:-$HOME/.config/symphony/rules}"

shipped_or_overlaid() {
  [ -f "$overlay_dir/$1" ] && { printf '%s' "$overlay_dir/$1"; return; }
  printf '%s' "$here/../rules/$1"
}

rules_file="${CLAUDE_WRITING_STYLE_FILE:-$(shipped_or_overlaid writing-style.md)}"
phrases_file="${CLAUDE_BANNED_PHRASES_FILE:-$(shipped_or_overlaid banned-phrases.txt)}"
[ -f "$rules_file" ] || exit 0

# Read from this script's own location, not from the writing style file, which
# can be pointed at a voice file kept anywhere.
rules_dir="$(cd -P "$here/../rules" 2>/dev/null && pwd)" || rules_dir=""

context=""
if [ -n "$rules_dir" ]; then
  context="Every rules file this system follows is in $rules_dir. Read one from"
  context+=$' there when you are told to read it by name.'
  if [ -d "$overlay_dir" ]; then
    overlay_abs="$(cd -P "$overlay_dir" && pwd)"
    context+=" A file of the same name in $overlay_abs replaces the one shipped"
    context+=$' there, so read that instead whenever it exists.'
  fi
  context+=$'\n\n'
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
