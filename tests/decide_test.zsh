#!/usr/bin/env zsh
# Tests for claude/bin/decide.sh. Every case runs inside a throwaway git repo so
# no real .decisions.md is ever created or appended to.
#
# Usage: zsh zsh/decide_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
DECIDE="$SCRIPT_DIR/../bin/decide.sh"

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

new_repo() {
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/decide_test.XXXXXX")"
  git -C "$REPO" init -q
  cd "$REPO"
}

drop_repo() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
}

echo "decide.sh:"

new_repo
"$DECIDE" "Where does the log live?" "In the working tree." >/dev/null
assert_equals "# Decisions

## Where does the log live?
In the working tree." "$(cat .decisions.md)" "creates the file with a header and the first entry"
drop_repo

new_repo
"$DECIDE" "First question?" "First answer." >/dev/null
"$DECIDE" "Second question?" "Second answer." >/dev/null
assert_equals "# Decisions

## First question?
First answer.

## Second question?
Second answer." "$(cat .decisions.md)" "appends the second entry below the first"
drop_repo

new_repo
mkdir -p deep/nested
cd deep/nested
"$DECIDE" "Run from a subdirectory?" "Still lands at the root." >/dev/null
cd "$REPO"
assert_equals "1" "$(ls .decisions.md deep/nested/.decisions.md 2>/dev/null | wc -l | tr -d ' ')" \
  "writes at the repo root when run from a subdirectory"
drop_repo

new_repo
"$DECIDE" "Only one argument?" >/dev/null 2>&1
assert_equals "64" "$?" "exits with a usage code when given the wrong argument count"
drop_repo

new_repo
"$DECIDE" "Blank decision?" "   " >/dev/null 2>&1
assert_equals "64" "$?" "refuses an entry whose decision is blank"
drop_repo

echo ""
echo "decide.sh --render:"

new_repo
"$DECIDE" "Where does the log live?" "In the working tree, rather than on the issue." >/dev/null
"$DECIDE" "Is an entry ever edited?" "Never, since a reversal is a new entry." >/dev/null
assert_equals "## Decision Log

### Where does the log live?

> In the working tree, rather than on the issue.

### Is an entry ever edited?

> Never, since a reversal is a new entry." "$("$DECIDE" --render)" "renders the section verbatim from the entries"
drop_repo

new_repo
"$DECIDE" --render >/dev/null 2>&1
assert_equals "1" "$?" "exits non-zero when there is no log to render"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
