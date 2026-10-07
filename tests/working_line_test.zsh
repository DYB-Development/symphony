#!/usr/bin/env zsh
# Tests for bin/working-line.sh. Every case writes its record into a throwaway
# directory, so no real record is touched.
#
# Usage: zsh tests/working_line_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WORKING="$SCRIPT_DIR/../bin/working-line.sh"

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

new_record() { export WORKING_LINE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/working_line_test.XXXXXX")"; }
drop_record() { rm -rf "$WORKING_LINE_DIR"; unset WORKING_LINE_DIR; }

tool_call() {
  jq -nc --arg session "$1" --arg tool "$2" --arg description "$3" \
    '{hook_event_name: "PreToolUse", session_id: $session, tool_name: $tool, tool_input: ({command: "true"} + (if $description == "" then {} else {description: $description} end))}' \
    | "$WORKING" record
}

echo "working-line.sh:"

new_record
tool_call s1 Bash "Run every test suite"
assert_equals "● working · Run every test suite" "$("$WORKING" show s1)" \
  "shows a working marker and the description of the session's tool call"
drop_record

new_record
tool_call s1 Bash "Run every test suite"
tool_call s1 Bash "Push the branch"
assert_equals "● working · Push the branch" "$("$WORKING" show s1)" "changes to the description of each new tool call"
drop_record

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
