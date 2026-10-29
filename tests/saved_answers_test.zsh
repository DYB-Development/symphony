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

new_store
repo_answers shop '{"version": 1, "answers": [
  {"name": "deploy", "question": "Where does Postgres run in production?", "answer": "On the managed host."}
]}'
git commit -q --allow-empty -m start
git worktree add -q -b feature/quotes "$WORK/shop-feature-quotes"
cd "$WORK/shop-feature-quotes"
assert_equals "shop: Where does Postgres run in production?
On the managed host." "$("$SEARCH" postgres)" "reads the answers named after the main clone from a linked worktree"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "full-suite", "question": "When does the full test suite run?", "answer": "Once, right before the pull request opens."}
]}'
repo_answers shop '{"version": 1, "answers": [
  {"name": "full-suite", "question": "When does the full test suite run?", "answer": "Never locally, CI runs it."}
]}'
assert_equals "shop: When does the full test suite run?
Never locally, CI runs it." "$("$SEARCH" full suite)" "prints only the repo answer when a default carries the same name"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "postgres", "question": "How do I start Postgres?", "answer": "Postgres starts with pgstart."}
]}'
assert_equals "|1" "$("$SEARCH" how do I deploy this; printf '|%s' "$?")" "ignores common words that every question shares"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "suite", "question": "When does the test suite run?", "answer": "Once."},
  {"name": "ci", "question": "When is CI watched after the test suite runs?", "answer": "Once it opens."}
]}'
assert_equals "default: When is CI watched after the test suite runs?
Once it opens.

default: When does the test suite run?
Once." "$("$SEARCH" watch CI suite)" "prints the entry sharing the most words first"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "one", "question": "Which branch first?", "answer": "1"},
  {"name": "two", "question": "Which branch second?", "answer": "2"},
  {"name": "three", "question": "Which branch third?", "answer": "3"},
  {"name": "four", "question": "Which branch fourth?", "answer": "4"},
  {"name": "five", "question": "Which branch fifth?", "answer": "5"},
  {"name": "six", "question": "Which branch sixth?", "answer": "6"}
]}'
assert_equals "5" "$("$SEARCH" branch | grep -c '^default: ')" "prints at most five entries"
drop_store

new_store
unset SYMPHONY_REPO_ANSWERS_DIR
export HOME="$WORK/home"
mkdir -p "$HOME/.config/symphony/answers"
printf '%s\n' '{"version": 1, "answers": [
  {"name": "deploy", "question": "Where does Postgres run in production?", "answer": "On the managed host."}
]}' > "$HOME/.config/symphony/answers/shop.json"
assert_equals "shop: Where does Postgres run in production?
On the managed host." "$("$SEARCH" postgres production)" "reads repo answers from the owner's symphony config folder by default"
drop_store

new_store
unset SYMPHONY_ANSWERS_DIR
assert_equals "default: Where do gems live on this machine?
gems live in ~/projects/gems" "$("$SEARCH" where do gems live | sed -n 1,2p)" "finds a shipped default answer"
drop_store

new_store
defaults '{"version": 1, "answers": [
  {"name": "database", "question": "Which database does the shop use?", "answer": "Postgres."},
  {"name": "replica", "question": "Where does the shop reporting replica run?", "answer": "On the second host."}
]}'
assert_equals "default: Which database does the shop use?
Postgres." "$("$SEARCH" --settles which database should the shop use for reports)" "prints only the entries sharing at least half of the search's words when asked which ones settle it"
drop_store

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
