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

assert_equals "Interruptions: 1,250" "$(rows 100 s1 interrupted 1000 160 s1 interrupted 250 | "$EFFORT" | grep '^Interruptions:')" "totals the turns interrupted"

assert_equals "Rejected tool calls: 1,250" "$(rows 100 s1 rejected 1000 160 s1 rejected 250 | "$EFFORT" | grep '^Rejected tool calls:')" "totals the tool calls rejected"

assert_equals "Claude working time: 1h 5m" "$(rows 100 s1 turn 3600000 5000 s1 turn 300000 | "$EFFORT" | grep '^Claude working time:')" "totals how long Claude's turns took"

assert_equals "Your active time: 5m" "$(rows 100 s1 turn 60000 400 s1 prompt 1 | "$EFFORT" | grep '^Your active time:')" "counts the time between a turn ending and the next prompt"

assert_equals "Your active time: 10m" "$(rows 100 s1 turn 60000 3700 s1 prompt 1 | "$EFFORT" | grep '^Your active time:')" "counts no more than ten minutes of one gap"

assert_equals "## Effort

- Sessions: 1
- Prompts: 1
- Words typed: 3
- Pasted blocks: 0
- Words pasted: 0
- Questions answered: 0
- Interruptions: 0
- Rejected tool calls: 0
- Claude working time: 2m
- Your active time: 5m" "$(rows 100 s1 turn 120000 400 s1 prompt 1 400 s1 typed 3 | "$EFFORT" --render)" "prints the PR body's Effort section"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
