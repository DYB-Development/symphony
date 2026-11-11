#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/repo-agents.sh"

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

STATE="$(mktemp -d "${TMPDIR:-/tmp}/repo_agents_test.XXXXXX")"
STATE="${STATE:A}"
export SYMPHONY_AGENTS_DIR="$STATE/agents"
mkdir -p "$SYMPHONY_AGENTS_DIR"
REPO="$STATE/shop"
git init -q "$REPO"
git -C "$REPO" commit -q --allow-empty -m init

payload() {
  jq -nc --arg type "$1" --arg cwd "${2:-$REPO}" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Agent", tool_input: {subagent_type: $type, prompt: "x"}, cwd: $cwd}'
}

decision() {
  payload "$@" | "$GATE" check | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

echo "repo-agents.sh:"

printf '{"block": ["shop-helper"]}' > "$SYMPHONY_AGENTS_DIR/shop.json"

assert_equals "deny" "$(decision shop-helper)" \
  "refuses an agent the repo's block list names"

printf '{"block": ["*"]}' > "$SYMPHONY_AGENTS_DIR/shop.json"
mkdir -p "$REPO/.claude/agents"
printf -- '---\nname: shop-reviewer\n---\n' > "$REPO/.claude/agents/shop-reviewer.md"

assert_equals "deny" "$(decision shop-reviewer)" \
  "refuses every agent the repo defines when the block list holds a star"

assert_equals "" "$(decision general-purpose)" \
  "lets through an agent the repo does not define when the block list holds a star"

git -C "$REPO" worktree add -q -b feature "$STATE/shop-feature"
printf -- '---\nname: shop-installer\n---\n' > "$REPO/.claude/agents/shop-installer.md"

assert_equals "deny" "$(decision shop-installer "$STATE/shop-feature")" \
  "refuses from a worktree an agent defined only in the repo's main clone"

rm -rf "$STATE"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
