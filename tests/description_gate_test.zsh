#!/usr/bin/env zsh
# Tests for bin/description-gate.sh.
#
# Usage: zsh tests/description_gate_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/description-gate.sh"

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

run() {
  jq -nc --argjson input "$1" '{session_id: "s1", tool_name: "Bash", tool_input: $input}' | "$GATE" check
}

echo "description-gate.sh check:"

assert_equals "deny" "$(run '{"command": "ls"}' | jq -r '.hookSpecificOutput.permissionDecision')" \
  "refuses a command with no description"

assert_equals "deny" "$(run '{"command": "ls", "description": "   "}' | jq -r '.hookSpecificOutput.permissionDecision')" \
  "refuses a command whose description is empty"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
