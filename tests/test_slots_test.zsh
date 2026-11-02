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
  export TEST_RUNS_FILE="$WORK/test-runs.tsv"
}

drop_ledger() {
  pkill -f "$WORK" 2>/dev/null
  rm -rf "$WORK"
  unset TEST_SLOTS_DIR TEST_SLOTS_TOTAL TEST_RUNS_FILE
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
assert_equals "5" "$(TEST_SLOTS_TOTAL=5 workers_given)" "takes the slot total from its setting"
drop_ledger

new_ledger
unset TEST_SLOTS_TOTAL
assert_equals "$(getconf _NPROCESSORS_ONLN)" "$(workers_given)" "takes the machine's processor count as the slot total when it is not set"
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
assert_equals $'Running tests with 12 workers\nthe tests' "$("$SLOTS" run echo "the tests")" \
  "prints the workers it gave on one line before the test output"
drop_ledger

new_ledger
"$SLOTS" run sh -c 'exit 7' > /dev/null
assert_equals "7" "$?" "exits with the test run's own exit status"
drop_ledger

new_ledger
"$SLOTS" run sh -c 'exit 3' > /dev/null
assert_equals "12" "$(workers_given)" "frees a run's slots when its tests fail"
drop_ledger

new_ledger
hold_slots
kill -TERM $HOLDER
wait $HOLDER
assert_equals "12" "$(workers_given)" "frees a run's slots when its tests are stopped"
drop_ledger

new_ledger
hold_slots
pkill -KILL -P $HOLDER
kill -KILL $HOLDER
wait $HOLDER 2>/dev/null
assert_equals "12" "$(workers_given)" "stops counting the slots of a run killed before it could give them back"
touch "$WORK/release"
drop_ledger

new_ledger
hold_slots
pkill -KILL -P $HOLDER
kill -KILL $HOLDER
wait $HOLDER 2>/dev/null
"$SLOTS" run true > /dev/null
assert_equals "0" "$(ls "$TEST_SLOTS_DIR/leases" | wc -l | tr -d ' ')" \
  "removes a finished run's lease when the next run starts"
drop_ledger

# A lease left by a run whose process number now belongs to this shell, which
# started at another time.
new_ledger
mkdir -p "$TEST_SLOTS_DIR/leases"
printf '%s\n%s\n%s\n' $$ "Thu Jan 1 00:00:00 2026" 12 > "$TEST_SLOTS_DIR/leases/$$"
assert_equals "12" "$(workers_given)" "stops counting a finished run's slots once its process number is given to a new process"
drop_ledger

new_ledger
mkdir -p "$TEST_SLOTS_DIR/leases"
printf 'not a lease\n' > "$TEST_SLOTS_DIR/leases/damaged"
assert_equals "12" "$(workers_given)" "does not count a damaged lease against the total"
drop_ledger

new_ledger
mkdir -p "$TEST_SLOTS_DIR/leases"
printf 'not a lease\n' > "$TEST_SLOTS_DIR/leases/damaged"
workers_given > /dev/null
assert_equals "absent" "$([[ -e "$TEST_SLOTS_DIR/leases/damaged" ]] && echo present || echo absent)" \
  "removes a damaged lease when the next run starts"
drop_ledger

# A ledger folder that cannot be made, since a file sits where it would go.
new_ledger
touch "$TEST_SLOTS_DIR"
assert_equals $'Running tests with 2 workers, since the slot ledger at '"$TEST_SLOTS_DIR"$' could not be used\nthe tests' \
  "$("$SLOTS" run echo "the tests" 2>&1)" \
  "runs with 2 workers and says so when the ledger cannot be used"
drop_ledger

new_ledger
touch "$TEST_SLOTS_DIR"
"$SLOTS" run sh -c 'exit 7' > /dev/null 2>&1
assert_equals "7" "$?" "exits with the test run's own status when the ledger cannot be used"
drop_ledger

new_ledger
mkdir -p "$TEST_SLOTS_DIR"
lockf -k "$TEST_SLOTS_DIR/lock" sh -c 'touch "$1/locked"; while [ ! -f "$1/release" ]; do sleep 0.05; done' _ "$WORK" &
LOCKER=$!
while [[ ! -f "$WORK/locked" ]]; do sleep 0.05; done
assert_equals "Running tests with 2 workers, since the slot ledger at $TEST_SLOTS_DIR stayed locked for 5 seconds" \
  "$("$SLOTS" run true 2>&1)" \
  "runs with 2 workers and says so when the ledger stays locked for 5 seconds"
touch "$WORK/release"
wait $LOCKER
drop_ledger

new_ledger
hold_slots
pkill -KILL -P $$ -f 'test-slots.sh run'
assert_equals "2" "$(workers_given)" "keeps counting a run's slots while its tests run on after its slot command is killed"
release_slots
drop_ledger

new_ledger
starters=()
for i in {1..6}; do
  "$SLOTS" run sh -c 'echo "$PARALLEL_WORKERS" > "$1/given.$$"; while [ ! -f "$1/release" ]; do sleep 0.05; done' _ "$WORK" > /dev/null &
  starters+=($!)
done
given=("$WORK"/given.*(N))
while (( $#given < 6 )); do sleep 0.05; given=("$WORK"/given.*(N)); done
touch "$WORK/release"
wait $starters
assert_equals "1" "$(cat "$WORK"/given.* | grep -cx 12)" "gives every slot to only one of several runs started at the same moment"
drop_ledger

# A Rails app whose bin/rails and bin/ci say what they ran and with how many
# workers, in place of running tests.
new_app() {
  new_ledger
  APP="$WORK/app"
  mkdir -p "$APP/bin"
  printf '#!/bin/sh\necho "rails $* with ${PARALLEL_WORKERS:-unset} workers"\n' > "$APP/bin/rails"
  printf '#!/bin/sh\necho "ci with ${PARALLEL_WORKERS:-unset} workers"\n' > "$APP/bin/ci"
  chmod +x "$APP/bin/rails" "$APP/bin/ci"
}

hook_output() {
  jq -nc --arg command "$1" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $command, timeout: 600000, run_in_background: true}}' \
    | "$SLOTS" wrap
}

# Runs a command the way the Bash tool would once the hook has seen it.
run_as_agent() {
  local command
  command=$(hook_output "$1" | jq -r '.hookSpecificOutput.updatedInput.command // empty')
  (cd "$APP" && bash -c "${command:-$1}")
}

echo ""
echo "test-slots.sh wrap:"

new_app
assert_equals $'Running tests with 12 workers\nrails test with 12 workers' "$(run_as_agent 'bin/rails test')" \
  "runs an agent's bin/rails test inside the slots"
drop_ledger

new_app
assert_equals "rails test test/models/quote_test.rb with 12 workers" "$(run_as_agent 'bin/rails test test/models/quote_test.rb' | tail -1)" \
  "runs an agent's bin/rails test of one file inside the slots"
drop_ledger

new_app
assert_equals "rails test:all with 12 workers" "$(run_as_agent 'bin/rails test:all' | tail -1)" \
  "runs an agent's bin/rails test:all inside the slots"
drop_ledger

new_app
assert_equals "rails test:system with 12 workers" "$(run_as_agent 'bin/rails test:system' | tail -1)" \
  "runs an agent's bin/rails test:system inside the slots"
drop_ledger

new_app
assert_equals "ci with 12 workers" "$(run_as_agent 'bin/ci' | tail -1)" "runs an agent's bin/ci inside the slots"
drop_ledger

new_app
assert_equals "rails test with 12 workers" "$(run_as_agent "cd $APP && bin/rails test" | tail -1)" \
  "runs an agent's test command that follows a cd inside the slots"
drop_ledger

new_app
assert_equals "rails test with 12 workers" "$(run_as_agent 'RAILS_ENV=test bin/rails test' | tail -1)" \
  "runs an agent's test command that sets an environment variable first inside the slots"
drop_ledger

# The branch, worktree, workers and exit status a run record line holds,
# leaving out its start time and duration.
recorded_runs() {
  [[ -f "$TEST_RUNS_FILE" ]] && cut -f1,2,3,6 "$TEST_RUNS_FILE"
}

new_app
git init -q -b feature/quotes "$APP"
run_as_agent 'bin/rails test' > /dev/null
assert_equals "feature/quotes	$(cd "$APP" && pwd -P)	12	0" "$(recorded_runs)" \
  "records a full-suite run's branch, worktree, workers and exit status"
drop_ledger

new_app
git init -q -b feature/quotes "$APP"
(cd "$WORK" && bash -c "$(hook_output "cd $APP && bin/rails test" | jq -r '.hookSpecificOutput.updatedInput.command')") > /dev/null
assert_equals "feature/quotes	$(cd "$APP" && pwd -P)" "$(recorded_runs | cut -f1,2)" \
  "records the branch and worktree the tests ran in when the command changed folder first"
drop_ledger

new_app
git init -q -b feature/quotes "$APP"
run_as_agent 'bin/rails test test/models/quote_test.rb' > /dev/null
assert_equals "" "$(recorded_runs)" "records nothing for a run of one named test file"
drop_ledger

new_app
git init -q -b feature/quotes "$APP"
printf '#!/bin/sh\ntouch "%s/started"\nwhile true; do sleep 0.05; done\n' "$WORK" > "$APP/bin/rails"
(cd "$APP" && exec "$SLOTS" run bin/rails test) > /dev/null &
RUN=$!
while [[ ! -f "$WORK/started" ]]; do sleep 0.05; done
kill -TERM $RUN
wait $RUN
assert_equals "interrupted" "$(recorded_runs | cut -f4)" "records a full-suite run stopped by a signal as interrupted"
drop_ledger

# A run record that cannot be written, since its folder is a file.
new_app
git init -q -b feature/quotes "$APP"
printf '#!/bin/sh\nexit 7\n' > "$APP/bin/rails"
touch "$WORK/runs"
export TEST_RUNS_FILE="$WORK/runs/test-runs.tsv"
run_as_agent 'bin/rails test' > /dev/null 2>&1
assert_equals "7" "$?" "exits with the test run's own status when the run record cannot be written"
drop_ledger

assert_equals "" "$(hook_output 'git status')" "leaves a command that runs no Rails tests as the agent wrote it"

assert_equals "" "$(hook_output 'bin/rails test && git push')" \
  "leaves a test command with more after the tests as the agent wrote it"

assert_equals "" "$(hook_output 'cd app;make && bin/rails test')" \
  "leaves a test command whose cd hides another command as the agent wrote it"

assert_equals "" "$(hook_output "$SLOTS run bin/rails test")" \
  "leaves a test command already run inside the slots as the agent wrote it"

assert_equals '{"timeout":600000,"run_in_background":true}' \
  "$(hook_output 'bin/rails test' | jq -c '.hookSpecificOutput.updatedInput | del(.command)')" \
  "keeps the agent's timeout and background setting on a rewritten test command"

assert_equals "allow" "$(hook_output 'bin/rails test' | jq -r '.hookSpecificOutput.permissionDecision')" \
  "approves a test command it rewrote, since the agent's allow rules no longer match it"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
