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

# The plugin carries its own hooks and the linked install writes them into the
# settings file, so finding both means every hook runs twice. Nothing else
# notices, because a plugin install never runs this package's installer.
installed_twice() {
  local settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  [ -f "$settings" ] || return 1
  command -v jq >/dev/null || return 1
  jq -e '((.enabledPlugins // {}) | keys | any(startswith("symphony@")))
         and ((.hooks // {}) | to_entries | any(.value[]?.hooks[]?.command
              | strings | contains("writing-style-hook.sh")))' \
    "$settings" >/dev/null 2>&1
}

context=""
if installed_twice; then
  context+="This system is installed twice, as a plugin and as links in "
  context+="${CLAUDE_CONFIG_DIR:-$HOME/.claude}, so every hook it registers runs "
  context+="twice. Remove one: either 'claude plugin uninstall symphony@symphony', "
  context+=$'or the links and this package\'s entries in settings.json.\n\n'
fi
if [ -n "$rules_dir" ]; then
  context+="Every rules file this system follows is in $rules_dir. Read one from"
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
