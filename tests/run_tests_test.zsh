#!/usr/bin/env zsh
# Tests for run_tests.sh. Every case runs a copy of the runner in a throwaway
# folder holding only the suites the case writes.
#
# Usage: zsh tests/run_tests_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
RUNNER="$SCRIPT_DIR/../run_tests.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  [[ "$1" == "$2" ]] && ok "$3" || { fail "$3"; printf '      want: %s\n      got:  %s\n' "$1" "$2"; }
}

new_repo() {
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/run_tests_test.XXXXXX")"
  REPO="${REPO:A}"
  cp "$RUNNER" "$REPO/run_tests.sh"
  mkdir -p "$REPO/tests"
}

suite() {
  printf '%s\n' "$2" > "$REPO/tests/$1_test.zsh"
}

waits_for() {
  print -r -- "touch $REPO/$1; for i in {1..50}; do [ -f $REPO/$2 ] && exit 0; sleep 0.1; done; exit 1"
}

echo "run_tests.sh:"

new_repo
suite a "$(waits_for a-started b-started)"
suite b "$(waits_for b-started a-started)"
"$REPO/run_tests.sh" >/dev/null 2>&1
assert_equals 0 "$?" "runs suites at the same time"
rm -rf "$REPO"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
