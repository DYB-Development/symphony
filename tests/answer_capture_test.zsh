#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CAPTURE="$SCRIPT_DIR/../bin/answer-capture.sh"

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
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/answer_capture_test.XXXXXX")"
  export SYMPHONY_REPO_ANSWERS_DIR="$WORK/repos"
  mkdir -p "$WORK/shop"
  git -C "$WORK/shop" init -q
  cd "$WORK"
}

drop_store() {
  cd "$SCRIPT_DIR"
  rm -rf "$WORK"
}

TODAY="$(date +%F)"

answered() {
  jq -nc --arg cwd "$WORK/shop" --arg event "${2:-PostToolUse}" --argjson response "$1" \
    '{session_id: "s1", cwd: $cwd, hook_event_name: $event, tool_name: "AskUserQuestion",
      tool_input: {questions: [{question: "Which database should the shop use?", options: [{label: "Postgres"}, {label: "MySQL"}]}]},
      tool_response: $response}' \
    | "$CAPTURE" record
}

review_list() {
  jq -c '.entries' "$SYMPHONY_REPO_ANSWERS_DIR/shop.review.json"
}

echo "answer-capture.sh record:"

new_store
answered '{"answers": {"Which database should the shop use?": "Postgres"}}'
assert_equals '[{"question":"Which database should the shop use?","answer":"Postgres","notes":"","date":"'"$TODAY"'","status":"answered"}]' \
  "$(review_list)" \
  "records an answered question with its answer and the date in the repo's review list"
drop_store

new_store
answered '{"answers": {"Which database should the shop use?": "Postgres"}}'
answered '{"answers": {"Which database should the shop use?": "MySQL"}}'
assert_equals '["Postgres","MySQL"]' "$(review_list | jq -c 'map(.answer)')" \
  "adds each answer after the ones already waiting for review"
drop_store

new_store
answered '{"answers": {"Which database should the shop use?": "Postgres"}, "annotations": {"Which database should the shop use?": {"notes": "Keep it on the same host as the app."}}}'
assert_equals "Keep it on the same host as the app." "$(review_list | jq -r '.[0].notes')" \
  "records the notes the owner added to an answer"
drop_store

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
