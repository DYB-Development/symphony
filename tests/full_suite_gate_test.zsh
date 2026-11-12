#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/full-suite-gate.sh"

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

from_agent() {
  jq -nc --arg command "$1" \
    '{hook_event_name: "PreToolUse", session_id: "s1", agent_id: "a1", agent_type: "general-purpose", tool_name: "Bash", tool_input: {command: $command, description: "Run tests"}}' \
    | "$GATE" check | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

from_main_session() {
  jq -nc --arg command "$1" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", tool_input: {command: $command, description: "Run tests"}}' \
    | "$GATE" check | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

echo "full-suite-gate.sh:"

assert_equals "" "$(from_main_session 'bin/rails test')" \
  "lets the main session run the whole suite"

assert_equals "deny" "$(from_agent 'bin/rails test')" \
  "refuses a subagent's run of the whole Rails suite"

assert_equals "deny" "$(from_agent 'cd ~/projects/shop-feature && PARALLEL_WORKERS=2 bin/rails test 2>&1 | tail -15')" \
  "refuses the whole suite after a cd, a setting and with its output piped"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
