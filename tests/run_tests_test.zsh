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

new_repo
for name in a b c; do
  suite $name "echo start >> $REPO/log; sleep 0.2; echo end >> $REPO/log"
done
PARALLEL_WORKERS=1 "$REPO/run_tests.sh" >/dev/null 2>&1
assert_equals "start end start end start end" "$(tr '\n' ' ' < "$REPO/log" | sed 's/ $//')" \
  "runs no more suites at once than its workers"
rm -rf "$REPO"

new_repo
suite good "exit 0"
suite bad "exit 1"
"$REPO/run_tests.sh" >/dev/null 2>&1
assert_equals 1 "$?" "exits non-zero when a suite fails"
rm -rf "$REPO"

new_repo
suite one "exit 0"
suite two "exit 0"
"$REPO/run_tests.sh" >/dev/null 2>&1
assert_equals 0 "$?" "exits zero when every suite passes"
rm -rf "$REPO"

new_repo
for name in a b; do
  suite $name "echo ${name}1; sleep 0.1; echo ${name}2; sleep 0.1; echo ${name}3; exit 1"
done
OUTPUT="$("$REPO/run_tests.sh" 2>&1)"
BLOCKS="$(print -r -- "$OUTPUT" | grep -E '^[ab][123]$' | tr '\n' ' ' | sed 's/ $//')"
[[ "$BLOCKS" == "a1 a2 a3 b1 b2 b3" || "$BLOCKS" == "b1 b2 b3 a1 a2 a3" ]] \
  && ok "prints each suite's output as one block" \
  || { fail "prints each suite's output as one block"; printf '      got:  %s\n' "$BLOCKS"; }
rm -rf "$REPO"

logging_suites() {
  for name in a b c d e f g h i j; do
    suite $name "echo $name >> $REPO/log"
  done
}

run_order() {
  rm -f "$REPO/log"
  PARALLEL_WORKERS=1 "$REPO/run_tests.sh" "$@" >/dev/null 2>&1
  tr '\n' ' ' < "$REPO/log" | sed 's/ $//'
}

new_repo
logging_suites
ORDER="$(run_order)"
[[ "$ORDER" != "a b c d e f g h i j" ]] && ok "runs the suites in a shuffled order" \
  || fail "runs the suites in a shuffled order"
rm -rf "$REPO"

new_repo
suite one "exit 0"
[[ "$("$REPO/run_tests.sh" 2>&1)" =~ "Run options: --seed [0-9]+" ]] \
  && ok "prints the seed it used" || fail "prints the seed it used"
rm -rf "$REPO"

new_repo
logging_suites
PRINTED="$(PARALLEL_WORKERS=1 "$REPO/run_tests.sh" 2>&1)"
FIRST="$(tr '\n' ' ' < "$REPO/log" | sed 's/ $//')"
SEED="$(print -r -- "$PRINTED" | sed -n 's/^Run options: --seed //p')"
assert_equals "$FIRST" "$(run_order --seed "$SEED")" "repeats a run's order when given its seed"
rm -rf "$REPO"

new_repo
logging_suites
assert_equals "c" "$(cd "$REPO" && run_order tests/c_test.zsh)" "runs only the suite whose path it is given"
rm -rf "$REPO"

new_repo
suite good "exit 0"
suite bad "exit 1"
assert_equals "./run_tests.sh tests/bad_test.zsh" "$("$REPO/run_tests.sh" 2>&1 | tail -1)" \
  "ends with the command that reruns a failed suite"
rm -rf "$REPO"

new_repo
suite good "echo passing-detail"
[[ "$("$REPO/run_tests.sh" 2>&1)" != *passing-detail* ]] \
  && ok "leaves a passing suite's output out" || fail "leaves a passing suite's output out"
rm -rf "$REPO"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
