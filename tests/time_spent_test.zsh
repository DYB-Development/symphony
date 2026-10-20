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

assert_equals "" "$(span 0 600 s1 tool "" Agent builder | "$TIME_SPENT" --render | grep builder)" \
  "renders no line of its own for an agent whose type does not end in -scribe"

assert_equals "## Time Spent

- Total: 10m
- Waiting on the owner: 0m
- Model time: 0m
- Tool calls: 0m
- pr-scribe: 10m" "$({ span 0 600 s1 tool "" Agent pr-scribe; span 60 360 s1 tool pr-scribe Bash "git diff"; } | "$TIME_SPENT" --render)" \
  "counts the whole of a scribe's run, its own tool calls included, in that scribe's line"

assert_equals "- Tool calls: 5m" "$(span 0 300 s1 tool builder Bash "bin/rails test" | "$TIME_SPENT" --render | grep '^- Tool calls:')" \
  "counts a tool call made by an agent other than a scribe as tool calls"

assert_equals "## Time Spent

- Total: 20m
- Waiting on the owner: 0m
- Model time: 16m
- Tool calls: 4m" "$({ span 0 600 s1 turn "" "" ""; span 120 360 s1 tool "" Bash "bin/rails test"; span 900 1500 s1 tool "" Agent builder; } | "$TIME_SPENT" --render)" \
  "counts the time in a turn or an agent run that no tool call covers as model time"

assert_equals "- Waiting on the owner: 10m" "$(span 0 3600 s1 wait "" "" "" | "$TIME_SPENT" --render | grep '^- Waiting on the owner:')" \
  "counts no more than ten minutes of one wait on the owner"

assert_equals "## Time Spent

- Total: 10m
- Waiting on the owner: 5m
- Model time: 0m
- Tool calls: 5m" "$({ span 0 600 s1 wait "" "" ""; span 0 600 s1 tool "" Bash "bin/pr-wait.sh"; } | "$TIME_SPENT" --render)" \
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

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
