#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
REVIEW="$SCRIPT_DIR/../bin/answers-review.sh"

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
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/answers_review_test.XXXXXX")"
  export SYMPHONY_REPO_ANSWERS_DIR="$WORK/repos"
  mkdir -p "$SYMPHONY_REPO_ANSWERS_DIR" "$WORK/shop"
  git -C "$WORK/shop" init -q
  cd "$WORK/shop"
}

drop_store() {
  cd "$SCRIPT_DIR"
  rm -rf "$WORK"
}

waiting() {
  jq -n --argjson entries "$1" '{version: 1, entries: $entries}' > "$SYMPHONY_REPO_ANSWERS_DIR/shop.review.json"
}

DATABASE='{"question": "Which database should the shop use?", "answer": "Postgres", "notes": "", "date": "2026-10-28", "status": "answered"}'

saved() {
  jq -c '.answers' "$SYMPHONY_REPO_ANSWERS_DIR/shop.json"
}

echo "answers-review.sh:"

new_store
waiting "[$DATABASE]"
printf 'a\ndatabase\n' | "$REVIEW" > /dev/null
assert_equals '[{"name":"database","question":"Which database should the shop use?","answer":"Postgres"}]' "$(saved)" \
  "adds an approved entry to the repo's answers under the name the owner types"
drop_store

pending() {
  jq -c '.entries' "$SYMPHONY_REPO_ANSWERS_DIR/shop.review.json"
}

new_store
waiting "[$DATABASE]"
printf 'a\ndatabase\n' | "$REVIEW" > /dev/null
assert_equals '[]' "$(pending)" "removes an approved entry from the review list"
drop_store

new_store
waiting "[$DATABASE]"
printf 'd\n' | "$REVIEW" > /dev/null
assert_equals '[]|[]' "$(pending)|$(saved)" "removes a dropped entry from the review list without saving it"
drop_store

new_store
waiting "[$DATABASE]"
printf 'e\nPostgres, started with pgstart.\na\ndatabase\n' | "$REVIEW" > /dev/null
assert_equals "Postgres, started with pgstart." "$(saved | jq -r '.[0].answer')" \
  "saves the wording the owner typed when editing before approving"
drop_store

BRANCH='{"question": "Which branch does the shop release from?", "answer": "main", "notes": "", "date": "2026-10-28", "status": "answered"}'

new_store
waiting "[$DATABASE, $BRANCH]"
printf 'd\na\nrelease-branch\n' | "$REVIEW" > /dev/null
assert_equals '["release-branch"]|[]' "$(saved | jq -c 'map(.name)')|$(pending)" \
  "takes each waiting entry in turn"
drop_store

new_store
waiting "[$DATABASE, $BRANCH]"
assert_equals "1 of 2, answered on 2026-10-28
Question: Which database should the shop use?
Answer: Postgres
Approve (a), edit (e) or drop (d)? 
2 of 2, answered on 2026-10-28
Question: Which branch does the shop release from?
Answer: main
Approve (a), edit (e) or drop (d)? " "$(printf 'd\n' | "$REVIEW")" \
  "shows an entry's question and answer and asks what to do with it"
drop_store

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
