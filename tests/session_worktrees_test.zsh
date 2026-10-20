#!/usr/bin/env zsh
# Tests for bin/session-worktrees.sh. Every case runs against a throwaway git
# repo and a throwaway Claude config directory, so no real index is touched.
#
# Usage: zsh tests/session_worktrees_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
INDEXER="$SCRIPT_DIR/../bin/session-worktrees.sh"

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

new_repo() {
  REPO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/session_worktrees_test.XXXXXX")" && pwd -P)"
  git -C "$REPO" init -q
  export CLAUDE_CONFIG_DIR="$REPO/config"
  INDEX="$CLAUDE_CONFIG_DIR/session-worktrees.tsv"
  TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/a-repo/session_1.jsonl"
}

drop_repo() {
  rm -rf "$REPO"
  unset CLAUDE_CONFIG_DIR
}

tool_call() {
  local cwd="$1" input="$2" agent="${3:-}"
  jq -nc --arg cwd "$cwd" --arg transcript "$TRANSCRIPT" --argjson input "$input" --arg agent "$agent" \
    '{hook_event_name: "PreToolUse", session_id: "session_1", transcript_path: $transcript, cwd: $cwd,
      tool_name: "Bash", tool_input: $input} + (if $agent == "" then {} else {agent_id: $agent} end)' \
    | "$INDEXER" record
}

index() { cat "$INDEX" 2>/dev/null; }

echo "session-worktrees.sh:"

new_repo
tool_call "$REPO" '{"command": "true"}'
assert_equals "$REPO	$TRANSCRIPT" "$(index)" \
  "records the worktree a session works in beside its transcript"
drop_repo

new_repo
tool_call "$REPO" '{"command": "true"}'
tool_call "$REPO" '{"command": "true"}'
assert_equals "$REPO	$TRANSCRIPT" "$(index)" \
  "records a transcript and worktree pair once however many tool calls it makes"
drop_repo

new_repo
OTHER="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/session_worktrees_test.XXXXXX")" && pwd -P)"
tool_call "$OTHER" "$(jq -nc --arg repo "$REPO" '{command: "git -C \($repo) status"}')"
assert_equals "$REPO	$TRANSCRIPT" "$(index)" \
  "records a worktree a command names from a session started outside it"
rm -rf "$OTHER"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
