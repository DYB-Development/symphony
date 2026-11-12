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

opens_question_window() {
  jq -nc '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t1", name: "AskUserQuestion", input: {questions: [{question: "Add the total to the receipt too?"}]}}]}}' >> "$TRANSCRIPT"
  jq -nc '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t1", content: "Yes"}]}}' >> "$TRANSCRIPT"
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

phrase_blocks() {
  new_transcript
  prompt "Add a total to the shop's invoice page."
  says "The invoice page now shows a total.

$1"
  stop
  drop_transcript
}

assert_equals "$BLOCK
$BLOCK
$BLOCK
$BLOCK
$BLOCK
$BLOCK
$BLOCK" \
  "$(phrase_blocks "Do you want the receipt done too." \
    ; phrase_blocks "Should I add it to the receipt next." \
    ; phrase_blocks "Shall I go on with the receipt." \
    ; phrase_blocks "Want me to add it to the receipt." \
    ; phrase_blocks "Would you like the receipt done as well." \
    ; phrase_blocks "Let me know if the receipt needs it." \
    ; phrase_blocks "Tell me if the receipt needs it.")" \
  "refuses a turn whose closing lines ask the owner in words with no question mark"

new_transcript
prompt "Add a total to the shop's invoice page."
says "The receipt should include it in the next release."
assert_equals "" "$(stop)" "counts an asking phrase only as whole words"
drop_transcript

new_transcript
prompt "Add a total to the shop's invoice page."
says "Why did the total go missing?

The invoice page summed nothing when an order had no lines.

It now shows a total of zero for an empty order.

The invoice tests cover both cases.

All of them pass."
assert_equals "" "$(stop)" "lets a turn stop when its question sits above the closing lines"
drop_transcript

new_transcript
prompt "Add a total to the shop's invoice page."
says "The invoice page now shows a total.

Should I also add it to the receipt?"
opens_question_window
assert_equals "" "$(stop)" "lets a turn stop when it opened a question window after the question"
drop_transcript

new_transcript
prompt "Add a total to the shop's invoice page."
says "Should I also add it to the receipt?"
prompt "Yes, and run the invoice tests."
jq -nc '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t2", name: "Bash", input: {command: "bin/test"}}]}}' >> "$TRANSCRIPT"
assert_equals "" "$(stop)" "reads only the turn that is ending, not a question from an earlier turn"
drop_transcript

new_transcript
prompt "Add a total to the shop's invoice page."
says "Should I also add it to the receipt?"
assert_equals "" "$(stop true)" "lets the turn stop when this hook already refused it once, so it never loops"
drop_transcript

new_transcript
rm "$TRANSCRIPT"
output=$(stop 2>&1)
code=$?
assert_equals "0 stop-check.sh: could not read the transcript, so the turn stopped unchecked" "$code $output" \
  "lets the turn stop with a warning when the transcript cannot be read"
drop_transcript

new_transcript
prompt "Make the confirm prompt ask before it deletes an order."
says "The delete command now asks first:

\`\`\`
Delete order 42?
Should I go on? [y/N]
\`\`\`"
assert_equals "" "$(stop)" "does not count a question quoted inside a code block"
drop_transcript

new_transcript
prompt "Why does the shop's invoice page show no total?"
says "The total is now shown on every invoice, which answers the question you asked:

> Why does the shop's invoice page show no total?"
assert_equals "" "$(stop)" "does not count a question quoted inside a blockquote"
drop_transcript

echo ""
echo "the Stop hooks in hooks.json:"

assert_equals '${CLAUDE_PLUGIN_ROOT}/bin/stop-check.sh check' \
  "$(jq -r '.hooks.Stop[].hooks[].command | select(test("stop-check"))' "$SCRIPT_DIR/../hooks/hooks.json")" \
  "registers the plain-text question check on Stop"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
