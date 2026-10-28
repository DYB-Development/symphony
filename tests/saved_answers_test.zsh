#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SEARCH="$SCRIPT_DIR/../bin/saved-answers.sh"

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

new_store() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/saved_answers_test.XXXXXX")"
  export SYMPHONY_ANSWERS_DIR="$WORK/defaults"
  export SYMPHONY_REPO_ANSWERS_DIR="$WORK/repos"
  mkdir -p "$SYMPHONY_ANSWERS_DIR" "$SYMPHONY_REPO_ANSWERS_DIR" "$WORK/shop"
  git -C "$WORK/shop" init -q
  cd "$WORK/shop"
}

drop_store() {
  cd "$SCRIPT_DIR"
  rm -rf "$WORK"
}

defaults() {
  printf '%s\n' "$1" > "$SYMPHONY_ANSWERS_DIR/defaults.json"
}

repo_answers() {
  printf '%s\n' "$2" > "$SYMPHONY_REPO_ANSWERS_DIR/$1.json"
}

echo "saved-answers.sh:"

new_store
defaults '{"version": 1, "answers": [
  {"name": "postgres", "question": "How do I start Postgres?", "answer": "Postgres starts with pgstart."}
]}'
assert_equals "default: How do I start Postgres?
Postgres starts with pgstart." "$("$SEARCH" start postgres)" "prints a default entry whose question shares a word"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "postgres", "question": "How do I start Postgres?", "answer": "Postgres starts with pgstart."}
]}'
assert_equals "|1" "$("$SEARCH" deploy target; printf '|%s' "$?")" "prints nothing and exits 1 when no question shares a word"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "postgres", "question": "How do I start Postgres?", "answer": "Postgres starts with pgstart."}
]}'
repo_answers shop '{"version": 1, "answers": [
  {"name": "deploy", "question": "Where does Postgres run in production?", "answer": "On the managed host."}
]}'
assert_equals "shop: Where does Postgres run in production?
On the managed host.

default: How do I start Postgres?
Postgres starts with pgstart." "$("$SEARCH" postgres)" "prints the repo's matching entries from the repo answers folder before the matching defaults"
drop_store

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
