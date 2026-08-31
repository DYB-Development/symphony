#!/usr/bin/env zsh
# Tests for claude/bin/decision-gate.sh. Every case runs inside a throwaway git
# repo with its own marker directory, so no real session state is touched.
#
# Usage: zsh zsh/decision_gate_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/decision-gate.sh"
DECIDE="$SCRIPT_DIR/../bin/decide.sh"

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

new_repo() {
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/decision_gate_test.XXXXXX")"
  export CLAUDE_DECISION_GATE_DIR="$REPO/.markers"
  git -C "$REPO" init -q
  cd "$REPO"
}

drop_repo() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
  unset CLAUDE_DECISION_GATE_DIR
}

arm()   { printf '{"session_id":"s1","tool_name":"AskUserQuestion"}' | "$GATE" arm; }
check() {
  jq -nc --arg cmd "$1" '{session_id: "s1", tool_name: "Bash", tool_input: {command: $cmd}}' | "$GATE" check
}

echo "decision-gate.sh arm:"

new_repo
arm >/dev/null
assert_equals "1" "$(ls "$CLAUDE_DECISION_GATE_DIR" | wc -l | tr -d ' ')" \
  "records a pending fork for the session"
drop_repo

new_repo
assert_contains "decide.sh" "$(arm)" "tells the session to record the fork now"
drop_repo

echo ""
echo "decision-gate.sh check:"

new_repo
arm >/dev/null
assert_contains '"permissionDecision":"deny"' "$(check 'git commit -m "wip"')" \
  "refuses a commit while the fork is unrecorded"
drop_repo

new_repo
arm >/dev/null
"$DECIDE" "Which road?" "The left one, over the right." >/dev/null
assert_equals "" "$(check 'git commit -m "wip"')" "lets the commit through once the decision is logged"
drop_repo

new_repo
arm >/dev/null
assert_equals "" "$(check 'NO_DECISION=1 git commit -m "wip"')" \
  "stands aside when the session declares the answer settled nothing"
drop_repo

new_repo
arm >/dev/null
assert_equals "" "$(check 'git status')" "leaves a command that is not a commit alone"
drop_repo

new_repo
arm >/dev/null
assert_contains '"permissionDecision":"deny"' \
  "$(check 'git commit -m "explain what NO_DECISION=1 is for"')" \
  "still refuses when the override is only mentioned in the message"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
