#!/usr/bin/env zsh
# Tests for bin/owner-turn.sh. Every case writes its record into a throwaway
# directory, so no real record is touched.
#
# Usage: zsh tests/owner_turn_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
TURN="$SCRIPT_DIR/../bin/owner-turn.sh"

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

echo "owner-turn.sh:"

output=$("$TURN" "lunch" "Eat something" 2>&1)
code=$?
assert_equals "64 owner-turn.sh: the kind is one of permission, question, pull request or plan" "$code $output" \
  "refuses a kind that is not one of the four, naming them"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
