#!/usr/bin/env zsh
# Tests for bin/scribe-step.sh and bin/agent-progress.sh. Every case writes its
# logs into a throwaway directory, so no real progress log is touched.
#
# Usage: zsh tests/agent_progress_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STEP="$SCRIPT_DIR/../bin/scribe-step.sh"

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

echo "scribe-step.sh:"

assert_equals "acme/quotes#42 · 3. Run every check" \
  "$("$STEP" "acme/quotes#42" "3. Run every check" 2>&1)" \
  "prints the target and the step it is given"

PROGRESS="$SCRIPT_DIR/../bin/agent-progress.sh"

new_dir() { LOGS="$(mktemp -d "${TMPDIR:-/tmp}/agent_progress_test.XXXXXX")"; }
drop_dir() { rm -rf "$LOGS"; }

bash_payload() {
  jq -nc --arg id "$1" --arg type "$2" --arg command "$3" \
    '{hook_event_name: "PreToolUse", session_id: "s1", agent_id: $id, agent_type: $type, tool_name: "Bash", tool_input: {command: $command}}'
}

record() {
  AGENT_PROGRESS_DIR="$LOGS" AGENT_PROGRESS_NOW="$1" "$PROGRESS" record
}

echo "agent-progress.sh record:"

new_dir
bash_payload a1 review-scribe '~/.claude/bin/scribe-step.sh "acme/quotes#42" "3. Run every check"' | record 1000
assert_equals $'1000\treview-scribe\tacme/quotes#42\t3. Run every check' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records a step marker against the agent that ran it"
drop_dir

new_dir
jq -nc '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", tool_input: {command: "~/.claude/bin/scribe-step.sh \"acme/quotes#42\" \"1. Read the diff\""}}' | record 1000
assert_equals "" "$(ls -A "$LOGS")" "records nothing for a command run outside a subagent"
drop_dir

new_dir
bash_payload a1 review-scribe '~/.claude/bin/judge-claims.sh /repo/.review-42.claims.json' | record 1000
assert_equals $'1000\treview-scribe\t\truns judge-claims' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records a symphony script a subagent runs"
drop_dir

new_dir
jq -nc '{hook_event_name: "SubagentStop", session_id: "s1", agent_id: "a1", agent_type: "review-scribe"}' | record 1000
assert_equals $'1000\treview-scribe\t\tfinished' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records that a subagent finished"
drop_dir

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
