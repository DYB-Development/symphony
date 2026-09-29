#!/usr/bin/env zsh
# Tests for bin/stray-test-workers.sh. Every case starts a sleeping process
# named like a Rails test worker, so no real test run is touched.
#
# Usage: zsh tests/stray_test_workers_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STRAY_TEST_WORKERS="$SCRIPT_DIR/../bin/stray-test-workers.sh"
MARK="stray_test_workers_test_$$"

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

start_orphaned_worker() {
  ( (exec -a "Rails test worker 9 - $MARK $1" sleep 300) & )
  sleep 0.5
}

running() {
  pgrep -f "$MARK $1" >/dev/null && echo running || echo stopped
}

stop_leftovers() {
  pkill -f "$MARK" 2>/dev/null
  sleep 0.2
}

echo "stray-test-workers.sh:"

start_orphaned_worker orphaned
"$STRAY_TEST_WORKERS" >/dev/null 2>&1
sleep 0.5
assert_equals "stopped" "$(running orphaned)" "stops a Rails test worker whose parent has gone"
stop_leftovers

(exec -a "Rails test worker 9 - $MARK watched" sleep 300) &
sleep 0.5
"$STRAY_TEST_WORKERS" >/dev/null 2>&1
sleep 0.5
assert_equals "running" "$(running watched)" "leaves a Rails test worker whose test run is still going"
stop_leftovers

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
