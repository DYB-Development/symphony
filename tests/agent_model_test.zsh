#!/usr/bin/env zsh
# Tests for bin/agent-model.sh.
#
# Usage: zsh tests/agent_model_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
HOOK="$SCRIPT_DIR/../bin/agent-model.sh"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent_model_test.XXXXXX")"
MODELS="$WORK/agent-models.json"

spawn() {
  local input="$1"
  jq -nc --argjson input "$input" '{session_id: "s1", tool_name: "Agent", tool_input: $input}' \
    | SYMPHONY_AGENT_MODELS_FILE="$MODELS" "$HOOK" set
}

echo "agent-model.sh set:"

printf '{"pr-scribe": "haiku"}' > "$MODELS"
assert_equals '{"prompt":"Write it","description":"Write the body","subagent_type":"pr-scribe","model":"haiku"}' \
  "$(spawn '{"prompt": "Write it", "description": "Write the body", "subagent_type": "pr-scribe"}' | jq -c '.hookSpecificOutput.updatedInput')" \
  "gives a named agent the model the file names for it"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
