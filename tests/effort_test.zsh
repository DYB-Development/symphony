#!/usr/bin/env zsh
# Tests for bin/effort.sh. Every case feeds it rows on standard input in the
# shape usage.sh --rows prints them, so no transcript is read.
#
# Usage: zsh tests/effort_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
EFFORT="$SCRIPT_DIR/../bin/effort.sh"

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

rows() {
  printf '%s\t%s\t%s\t%s\n' "$@"
}

echo "effort.sh:"

assert_equals "Prompts: 2" "$(rows 100 s1 prompt 1 160 s1 prompt 1 | "$EFFORT" | grep '^Prompts:')" "counts the prompts typed"

assert_equals "Sessions: 2" "$(rows 100 s1 prompt 1 160 s1 prompt 1 900 s2 prompt 1 | "$EFFORT" | grep '^Sessions:')" "counts the sessions the prompts were typed in"

assert_equals "Words typed: 1,250" "$(rows 100 s1 typed 1000 160 s1 typed 250 | "$EFFORT" | grep '^Words typed:')" "totals the words typed"

assert_equals "Pasted blocks: 1,250" "$(rows 100 s1 pasted 1000 160 s1 pasted 250 | "$EFFORT" | grep '^Pasted blocks:')" "totals the blocks pasted"

assert_equals "Words pasted: 1,250" "$(rows 100 s1 pasted-words 1000 160 s1 pasted-words 250 | "$EFFORT" | grep '^Words pasted:')" "totals the words pasted"

assert_equals "Questions answered: 1,250" "$(rows 100 s1 answered 1000 160 s1 answered 250 | "$EFFORT" | grep '^Questions answered:')" "totals the questions answered"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
