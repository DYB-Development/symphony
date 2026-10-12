#!/usr/bin/env zsh
# Tests for bin/work-agent.sh. Every case runs against a stub claude that writes
# down how it was started and where, and a throwaway repo with the task's
# worktree, so no model runs.
#
# Usage: zsh tests/work_agent_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
AGENT="$SCRIPT_DIR/../bin/work-agent.sh"

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

setup() {
  WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/work_agent_test.XXXXXX")" && pwd -P)"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/../args"
pwd > "$(dirname "$0")/../ran_in"
printf '{"result":"Wrote one test.","usage":{"input_tokens":3,"output_tokens":40,"cache_read_input_tokens":500,"cache_creation_input_tokens":4000},"modelUsage":{"claude-sonnet-5-5":{}}}'
STUB
  chmod +x "$WORK/bin/claude"
  export SYMPHONY_CLAUDE="$WORK/bin/claude"
  git init -q --template= -b main "$WORK/quotes"
  git -C "$WORK/quotes" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$WORK/quotes" worktree add -q -b 7-export-quotes "$WORK/quotes-7-export-quotes"
  export WORK_ITEM_ID=7
  export PIPELINE_STEP="$(jq -nc '{id: "write_test", kind: "agent", agent: "test-writer", check: "work-new-test-fails",
    work: {title: "Export quotes", request: "Reps want quotes as CSV.", acceptance_criteria: "A rep downloads a CSV"},
    agent_version: {number: 2, instructions: "You write ONE test.", tools: ["Read", "Write"], model: "claude-sonnet-5-5"}}')"
  cd "$WORK/quotes"
}

teardown() {
  cd "$SCRIPT_DIR"
  rm -rf "$WORK"
  unset SYMPHONY_CLAUDE WORK_ITEM_ID PIPELINE_STEP
}

arg_after() { awk -v flag="$1" 'found { print; exit } $0 == flag { found = 1 }' "$WORK/args"; }

echo "work-agent.sh:"

setup
"$AGENT" >/dev/null 2>&1
assert_equals "You write ONE test." "$(arg_after --system-prompt)" "uses the version's instructions as the session's whole system prompt"
teardown

setup
"$AGENT" >/dev/null 2>&1
assert_equals "Read,Write Read,Write" "$(arg_after --tools) $(arg_after --allowedTools)" "gives the session only the tools its version lists, allowed without a prompt"
teardown

setup
"$AGENT" >/dev/null 2>&1
assert_equals "setting-sources:[] strict-mcp:yes skills-off:yes" "setting-sources:[$(arg_after --setting-sources)] strict-mcp:$(grep -qx -- --strict-mcp-config "$WORK/args" && echo yes || echo no) skills-off:$(grep -qx -- --disable-slash-commands "$WORK/args" && echo yes || echo no)" \
  "loads none of the owner's settings, hooks, rules, MCP servers or skills"
teardown

setup
"$AGENT" >/dev/null 2>&1
assert_equals "$WORK/quotes-7-export-quotes" "$(cat "$WORK/ran_in" 2>/dev/null)" "runs the session in the task's worktree"
teardown

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
