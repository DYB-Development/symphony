#!/usr/bin/env zsh
# Tests for bin/test-slots.sh. Every case keeps its leases in a throwaway
# directory, so no real lease is touched.
#
# Usage: zsh tests/test_slots_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SLOTS="$SCRIPT_DIR/../bin/test-slots.sh"

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

new_ledger() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/test_slots_test.XXXXXX")"
  export TEST_SLOTS_DIR="$WORK/slots"
  export TEST_SLOTS_TOTAL=12
}

drop_ledger() {
  rm -rf "$WORK"
  unset TEST_SLOTS_DIR TEST_SLOTS_TOTAL
}

workers_given() {
  "$SLOTS" run sh -c 'echo "$PARALLEL_WORKERS"' | tail -1
}

echo "test-slots.sh run:"

new_ledger
assert_equals "12" "$(workers_given)" "gives a run every slot when no other run holds any"
drop_ledger

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
