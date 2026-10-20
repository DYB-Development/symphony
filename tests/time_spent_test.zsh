#!/usr/bin/env zsh
# Tests for bin/time-spent.sh. Every case feeds it spans on standard input in
# the shape usage.sh --spans prints them, so no transcript is read.
#
# Usage: zsh tests/time_spent_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
TIME_SPENT="$SCRIPT_DIR/../bin/time-spent.sh"

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

span() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

echo "time-spent.sh:"

assert_equals "## Time Spent

- Total: 1h 30m
- Waiting on the owner: 0m
- Model time: 0m
- Tool calls: 1h 30m" "$(span 0 5400 s1 tool "" Bash "bin/rails test" | "$TIME_SPENT" --render)" \
  "renders a total and one line per kind"

assert_equals "## Time Spent

- Total: 15m
- Waiting on the owner: 0m
- Model time: 0m
- Tool calls: 0m
- pr-scribe: 5m
- review-scribe: 10m" "$({ span 0 600 s1 tool "" Agent review-scribe; span 600 900 s1 tool "" Agent pr-scribe; } | "$TIME_SPENT" --render)" \
  "renders one line per scribe that ran, named by its agent type"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
