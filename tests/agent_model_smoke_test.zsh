#!/usr/bin/env zsh
# Smoke test: the hook registered on the Agent tool in hooks/hooks.json sets a
# spawned agent's model from the owner's agent models file.
#
# Usage: zsh tests/agent_model_smoke_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent_model_smoke.XXXXXX")"
MODELS="$WORK/agent-models.json"

registered="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Agent") | .hooks[].command' "$ROOT/hooks/hooks.json")"
command="${registered//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"

spawn() {
  jq -nc --arg name "$1" \
    '{session_id: "s1", hook_event_name: "PreToolUse", tool_name: "Agent", tool_input: {prompt: "Build it", description: "Build the page", subagent_type: $name}}' \
    | SYMPHONY_AGENT_MODELS_FILE="$MODELS" bash -c "$command"
}

echo "the Agent hook in hooks.json:"

printf '{"keystone_ui-develop": "sonnet"}' > "$MODELS"
assert_equals "sonnet" \
  "$(spawn keystone_ui-develop | jq -r '.hookSpecificOutput.updatedInput.model')" \
  "spawns an agent another package installed on the model the file names for it"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
