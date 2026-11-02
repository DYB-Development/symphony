#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/owner-question.sh"

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

STATE="$(mktemp -d "${TMPDIR:-/tmp}/owner_question_test.XXXXXX")"
trap 'rm -rf "$STATE"' EXIT
export OWNER_QUESTION_DIR="$STATE/marks"

reset_marks() { rm -rf "$OWNER_QUESTION_DIR"; }

prompt() {
  jq -nc --arg text "$1" '{hook_event_name: "UserPromptSubmit", session_id: "s1", prompt: $text}' | "$GATE" record
}

asked() {
  if "$GATE" asked s1; then echo yes; else echo no; fi
}

echo "owner-question.sh record:"

reset_marks; prompt "are you following the rules?"
assert_equals "yes" "$(asked)" "marks a prompt ending in a question mark as a question"

reset_marks; prompt "so again what is the plan"
assert_equals "yes" "$(asked)" "marks a prompt opening with a question word and no question mark as a question"

reset_marks; prompt "are you ok?"; prompt "go ahead with the plan"
assert_equals "no" "$(asked)" "removes the mark when the owner's next prompt is an instruction"

reset_marks; prompt "are you ok?"; prompt "<task-notification>
<task-id>b1</task-id>
<status>completed</status>
</task-notification>"
assert_equals "yes" "$(asked)" "keeps the mark when a background task notification arrives"

reset_marks; prompt "This keeps failing. How do we solve this."
assert_equals "yes" "$(asked)" "reads the last sentence of a prompt to tell whether it is a question"

reset_marks; prompt "Why is this broken?
<pasted_content id=\"a1\">
ran the suite.
</pasted_content id=\"a1\">"
assert_equals "yes" "$(asked)" "leaves pasted text out when reading the prompt"

reset_marks; prompt "stop"
assert_equals "yes" "$(asked)" "marks a prompt telling the session to stop"

tool_call() {
  jq -nc --arg tool "$1" --argjson input "${2:-{\}}" --arg agent "${3:-}" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $tool, tool_input: $input, agent_id: $agent}' | "$GATE" check
}

decision() {
  tool_call "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

echo "owner-question.sh check:"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(decision Edit '{"file_path":"/a"}')" "refuses a file edit after the owner asks a question"

reset_marks; prompt "are you ok?"
assert_equals "" "$(decision Read '{"file_path":"/a"}')" "lets a file be read while the question is being answered"

stop_turn() {
  jq -nc '{hook_event_name: "Stop", session_id: "s1"}' | "$GATE" stop
}

reset_marks; prompt "are you ok?"; stop_turn
assert_equals "deny" "$(decision Read '{"file_path":"/a"}')" "refuses a read once the turn that answered the question has ended"

reset_marks; prompt "are you ok?"
assert_equals "" "$(decision Edit '{"file_path":"/a"}' agent-1)" "lets a running subagent carry on"

bash_decision() {
  decision Bash "$(jq -nc --arg c "$1" '{command: $c}')"
}

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git -C /a status --short | head -3')" "lets a read-only shell command run while the question is being answered"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'git status && git commit -m done')" "refuses a shell command that changes something after a read-only one"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'cat a > b')" "refuses a shell command that writes a file through a redirect"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
