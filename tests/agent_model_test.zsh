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

assert_equals "" \
  "$(spawn '{"prompt": "Look", "description": "Look around", "subagent_type": "Explore"}')" \
  "leaves an agent the file does not name on the model it would run on"

assert_equals "" \
  "$(spawn '{"prompt": "Write it", "description": "Write the body", "subagent_type": "pr-scribe", "model": "opus"}')" \
  "leaves a spawn that names its own model on that model"

rm -f "$MODELS"
spawn '{"prompt": "Write it", "description": "Write the body", "subagent_type": "pr-scribe"}' >/dev/null 2>&1
assert_equals "0" "$?" "lets the spawn through when there is no agent models file"

printf 'pr-scribe: haiku\n' > "$MODELS"
spawn '{"prompt": "Write it", "description": "Write the body", "subagent_type": "pr-scribe"}' >/dev/null 2>&1
assert_equals "0" "$?" "lets the spawn through when the agent models file is not JSON"

printf '{"pr-scribe": "fastest"}' > "$MODELS"
assert_equals "" \
  "$(spawn '{"prompt": "Write it", "description": "Write the body", "subagent_type": "pr-scribe"}')" \
  "leaves an agent on its usual model when the file names no haiku, sonnet or opus for it"

echo ""
echo "agent-model.sh lookup:"

printf '{"read-draft": "sonnet"}' > "$MODELS"
assert_equals "sonnet" \
  "$(SYMPHONY_AGENT_MODELS_FILE="$MODELS" "$HOOK" lookup read-draft opus)" \
  "prints the model the file names for a script's own name"

assert_equals "opus" \
  "$(SYMPHONY_AGENT_MODELS_FILE="$MODELS" "$HOOK" lookup judge-claims opus)" \
  "prints the fallback when the file does not name the script"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
