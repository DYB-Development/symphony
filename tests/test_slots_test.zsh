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

# Starts a run that holds its slots until release_slots, and waits until its
# command has started.
hold_slots() {
  rm -f "$WORK/held" "$WORK/release"
  "$SLOTS" run sh -c 'touch "$1/held"; while [ ! -f "$1/release" ]; do sleep 0.05; done' _ "$WORK" > /dev/null &
  HOLDER=$!
  while [[ ! -f "$WORK/held" ]]; do sleep 0.05; done
}

release_slots() {
  touch "$WORK/release"
  wait $HOLDER
}

echo "test-slots.sh run:"

new_ledger
assert_equals "12" "$(workers_given)" "gives a run every slot when no other run holds any"
drop_ledger

new_ledger
hold_slots
assert_equals "4" "$(TEST_SLOTS_TOTAL=16 workers_given)" "gives a run only the slots other runs do not hold"
release_slots
drop_ledger

new_ledger
hold_slots
assert_equals "2" "$(workers_given)" "gives a run 2 slots when other runs hold every slot"
release_slots
drop_ledger

new_ledger
hold_slots
workers_given > /dev/null
kill -0 $HOLDER 2>/dev/null
assert_equals "0" "$?" "starts a run's tests while other runs still hold every slot"
release_slots
drop_ledger

new_ledger
"$SLOTS" run sh -c 'exit 3' > /dev/null
assert_equals "12" "$(workers_given)" "frees a run's slots when its tests fail"
drop_ledger

new_ledger
hold_slots
pkill -TERM -P $HOLDER
wait $HOLDER
assert_equals "12" "$(workers_given)" "frees a run's slots when its tests are stopped"
drop_ledger

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
