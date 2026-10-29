#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
BLOCK="$SCRIPT_DIR/../bin/review-block.sh"

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

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

new_state() {
  STATE="$(mktemp -d "${TMPDIR:-/tmp}/review_block_test.XXXXXX")"
  export CLAUDE_REVIEW_BLOCK_DIR="$STATE/marks"
  REPO="$STATE/shop"
  mkdir -p "$REPO"
}

drop_state() {
  rm -rf "$STATE"
  unset CLAUDE_REVIEW_BLOCK_DIR
}

start() {
  jq -nc --arg type "${2:-review-scribe}" --arg prompt "Repo: acme/shop, PR 12, job: review" \
    '{session_id: $ARGS.positional[0], tool_name: "Agent", tool_input: {subagent_type: $type, prompt: $prompt}}' \
    --args "$1" | "$BLOCK" start
}

marks() { ls "$CLAUDE_REVIEW_BLOCK_DIR" 2>/dev/null | wc -l | tr -d ' '; }

echo "review-block.sh start:"

new_state
start s1 >/dev/null
assert_equals "1" "$(marks)" "marks the session as reviewing when it spawns the review scribe"
drop_state

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
