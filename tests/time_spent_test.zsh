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

one_minute_each() {
  local tool="$1" at=0 command
  shift
  for command in "$@"; do
    span "$at" $((at + 60)) s1 tool "" "$tool" "$command"
    at=$((at + 60))
  done
}

echo "time-spent.sh:"

assert_equals "## Time Spent

- Total: 1h 30m
- Waiting on the owner: 0m
- Model time: 0m
- Worktree setup: 0m
- Reading: 0m
- Test-first cycles: 0m
- Commits: 0m
- Ticking criteria and recording decisions: 0m
- Full-suite checks: 0m
- Other tool calls: 1h 30m" "$(span 0 5400 s1 tool "" Bash "bin/pr-wait.sh" | "$TIME_SPENT" --render)" \
  "renders a total and one line per kind"

assert_equals "## Time Spent

- Total: 15m
- Waiting on the owner: 0m
- Model time: 0m
- Worktree setup: 0m
- Reading: 0m
- Test-first cycles: 0m
- Commits: 0m
- Ticking criteria and recording decisions: 0m
- Full-suite checks: 0m
- Other tool calls: 0m
- pr-scribe: 5m
- review-scribe: 10m" "$({ span 0 600 s1 tool "" Agent review-scribe; span 600 900 s1 tool "" Agent pr-scribe; } | "$TIME_SPENT" --render)" \
  "renders one line per scribe that ran, named by its agent type"

assert_equals "" "$(span 0 600 s1 tool "" Agent builder | "$TIME_SPENT" --render | grep builder)" \
  "renders no line of its own for an agent whose type does not end in -scribe"

assert_equals "## Time Spent

- Total: 10m
- Waiting on the owner: 0m
- Model time: 0m
- Worktree setup: 0m
- Reading: 0m
- Test-first cycles: 0m
- Commits: 0m
- Ticking criteria and recording decisions: 0m
- Full-suite checks: 0m
- Other tool calls: 0m
- pr-scribe: 10m" "$({ span 0 600 s1 tool "" Agent pr-scribe; span 60 360 s1 tool pr-scribe Bash "git diff"; } | "$TIME_SPENT" --render)" \
  "counts the whole of a scribe's run, its own tool calls included, in that scribe's line"

assert_equals "- Other tool calls: 5m" "$(span 0 300 s1 tool builder Bash "bin/pr-wait.sh" | "$TIME_SPENT" --render | grep '^- Other tool calls:')" \
  "counts a tool call made by an agent other than a scribe as tool calls"

assert_equals "## Time Spent

- Total: 20m
- Waiting on the owner: 0m
- Model time: 16m
- Worktree setup: 0m
- Reading: 0m
- Test-first cycles: 0m
- Commits: 0m
- Ticking criteria and recording decisions: 0m
- Full-suite checks: 0m
- Other tool calls: 4m" "$({ span 0 600 s1 turn "" "" ""; span 120 360 s1 tool "" Bash "bin/pr-wait.sh"; span 900 1500 s1 tool "" Agent builder; } | "$TIME_SPENT" --render)" \
  "counts the time in a turn or an agent run that no tool call covers as model time"

assert_equals "- Waiting on the owner: 10m" "$(span 0 3600 s1 wait "" "" "" | "$TIME_SPENT" --render | grep '^- Waiting on the owner:')" \
  "counts no more than ten minutes of one wait on the owner"

assert_equals "## Time Spent

- Total: 10m
- Waiting on the owner: 5m
- Model time: 0m
- Worktree setup: 0m
- Reading: 0m
- Test-first cycles: 0m
- Commits: 0m
- Ticking criteria and recording decisions: 0m
- Full-suite checks: 0m
- Other tool calls: 5m" "$({ span 0 600 s1 wait "" "" ""; span 0 600 s1 tool "" Bash "bin/pr-wait.sh"; } | "$TIME_SPENT" --render)" \
  "splits a stretch two spans share evenly between them"

minutes_of_kinds_and_total() {
  awk -F ': ' '
    /^- / {
      minutes = 0
      count = split($2, part, " ")
      for (index_ = 1; index_ <= count; index_++)
        minutes += part[index_] ~ /h$/ ? part[index_] * 60 : part[index_] + 0
      if ($1 == "- Total") total = minutes
      else kinds += minutes
    }
    END { print kinds, total }
  '
}

assert_equals "3 3" "$({ span 0 90 s1 tool "" Bash "git status"; span 200 290 s1 wait "" "" ""; } | "$TIME_SPENT" --render | minutes_of_kinds_and_total)" \
  "renders kinds whose minutes add up to the total"

assert_equals "## Time Spent

Not measured." "$(: | "$TIME_SPENT" --render)" "renders Not measured when there is no span on the branch"

assert_equals "- Worktree setup: 5m" "$(one_minute_each Bash "bundle install" "bun run build" \
  "git -C ~/projects/app worktree add -b feat/x ~/projects/app-feat-x" \
  "~/.claude/bin/worktree-databases.sh create ~/projects/app-feat-x" "bin/rails db:migrate" |
  "$TIME_SPENT" --render | grep '^- Worktree setup:')" \
  "counts installing, building, adding a worktree, creating its databases and migrating as worktree setup"

assert_equals "- Reading: 6m" "$({ span 0 60 s1 tool "" Read ""; span 60 120 s1 tool "" Grep ""
  span 120 180 s1 tool "" Glob ""; span 180 240 s1 tool "" Bash "cat README.md"
  span 240 300 s1 tool "" Bash "cd ~/projects/app && git log --oneline"
  span 300 360 s1 tool "" Bash "sed -n 1,20p bin/usage.sh"; } |
  "$TIME_SPENT" --render | grep '^- Reading:')" \
  "counts reading a file, searching files and printing files or history as reading"

assert_equals "- Test-first cycles: 5m" "$({ span 0 60 s1 tool "" Edit ""; span 60 120 s1 tool "" Write ""
  span 120 180 s1 tool "" Bash "cd ~/projects/app && zsh tests/usage_test.zsh 2>&1 | tail -1"
  span 180 240 s1 tool "" Bash "bin/rails test test/models/quote_test.rb"
  span 240 300 s1 tool "" Bash "./run_tests.sh tests/usage_test.zsh"; } |
  "$TIME_SPENT" --render | grep '^- Test-first cycles:')" \
  "counts editing or writing a file and running one named test file as test-first cycles"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
