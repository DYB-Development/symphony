#!/usr/bin/env zsh
# Tests for bin/stop-check.sh. Every case writes its transcript into a
# throwaway directory, so no real transcript is read.
#
# Usage: zsh tests/stop_check_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CHECK="$SCRIPT_DIR/../bin/stop-check.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      expected: %s\n' "${(qqq)expected}"
    printf '      actual:   %s\n' "${(qqq)actual}"
  fi
}

new_transcript() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/stop_check_test.XXXXXX")"
  TRANSCRIPT="$WORK/session.jsonl"
  : > "$TRANSCRIPT"
}

drop_transcript() {
  rm -rf "$WORK"
}

prompt() {
  jq -nc --arg text "$1" '{type: "user", message: {role: "user", content: $text}}' >> "$TRANSCRIPT"
}

says() {
  jq -nc --arg text "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $text}]}}' >> "$TRANSCRIPT"
}

stop() {
  jq -nc --arg path "$TRANSCRIPT" --argjson active "${1:-false}" \
    '{hook_event_name: "Stop", session_id: "s1", transcript_path: $path, stop_hook_active: $active}' \
    | "$CHECK" check
}

BLOCK='{"decision":"block","reason":"This turn ends by asking the owner something in plain text, and nothing tells the owner a question is waiting. Keep working on the task you were given. If you truly need the owner to decide something before you can go on, ask in a question window with AskUserQuestion and lay out the options."}'

echo "stop-check.sh check:"

new_transcript
prompt "Add a total to the shop's invoice page."
says "The invoice page now shows a total.

Should I also add it to the receipt?"
assert_equals "$BLOCK" "$(stop)" "refuses a turn whose last line asks the owner a question"
drop_transcript

new_transcript
prompt "Add a total to the shop's invoice page."
says "The invoice page now shows a total."
assert_equals "" "$(stop)" "lets a turn that ends in a statement stop"
drop_transcript

echo ""
echo "the Stop hooks in hooks.json:"

assert_equals '${CLAUDE_PLUGIN_ROOT}/bin/stop-check.sh check' \
  "$(jq -r '.hooks.Stop[].hooks[].command | select(test("stop-check"))' "$SCRIPT_DIR/../hooks/hooks.json")" \
  "registers the plain-text question check on Stop"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
