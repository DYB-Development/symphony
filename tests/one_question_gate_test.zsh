#!/usr/bin/env zsh
# Tests for bin/one-question-gate.sh.
#
# Usage: zsh tests/one_question_gate_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/one-question-gate.sh"

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

ask() {
  jq -nc --argjson n "$1" \
    '{session_id: "s1", tool_name: "AskUserQuestion", tool_input: {questions: [range($n) | {question: "Which one \(.)?"}]}}' \
    | "$GATE" check
}

echo "one-question-gate.sh check:"

assert_equals "deny" "$(ask 2 | jq -r '.hookSpecificOutput.permissionDecision')" \
  "refuses a prompt holding two questions"

assert_equals "Ask one question, then wait for the answer before asking the next." \
  "$(ask 3 | jq -r '.hookSpecificOutput.permissionDecisionReason')" \
  "tells the agent to ask one question and wait for its answer"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
