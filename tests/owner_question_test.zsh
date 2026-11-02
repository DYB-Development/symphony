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

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
