#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/answer-gate.sh"

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
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/answer_gate_test.XXXXXX")"
  export SYMPHONY_ANSWERS_DIR="$WORK/defaults"
  export SYMPHONY_REPO_ANSWERS_DIR="$WORK/repos"
  mkdir -p "$SYMPHONY_ANSWERS_DIR" "$SYMPHONY_REPO_ANSWERS_DIR" "$WORK/shop"
  git -C "$WORK/shop" init -q
  printf '%s\n' '{"version": 1, "answers": []}' > "$SYMPHONY_ANSWERS_DIR/defaults.json"
  printf '%s\n' '{"version": 1, "answers": [
    {"name": "database", "question": "Which database does the shop use?", "answer": "Postgres, started with pgstart."}
  ]}' > "$SYMPHONY_REPO_ANSWERS_DIR/shop.json"
  cd "$WORK"
}

drop_store() {
  cd "$SCRIPT_DIR"
  rm -rf "$WORK"
}

ask() {
  jq -nc --arg cwd "$WORK/shop" --argjson questions "$1" \
    '{session_id: "s1", cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: $questions}}' \
    | "$GATE" check
}

SETTLED='[{"question": "Which database should the shop use?", "options": [{"label": "Postgres"}, {"label": "MySQL"}]}]'

echo "answer-gate.sh check:"

new_store
assert_equals "deny" "$(ask "$SETTLED" | jq -r '.hookSpecificOutput.permissionDecision')" \
  "refuses a question a saved answer settles"
drop_store

new_store
assert_equals "The owner has already answered this question. Use the saved answer below instead of asking.

shop: Which database does the shop use?
Postgres, started with pgstart.

If this saved answer does not fit, rephrase the question to say why it differs." \
  "$(ask "$SETTLED" | jq -r '.hookSpecificOutput.permissionDecisionReason')" \
  "quotes the saved question and answer, tells the session to use it, and says how to get past a wrong match"
drop_store

new_store
assert_equals "|0" "$(ask '[{"question": "Which branch should the release go out from?"}]'; printf '|%s' "$?")" \
  "lets a question through when no saved answer settles it"
drop_store

new_store
assert_equals "" "$(ask '[{"question": "Which database should the shop use?"}, {"question": "Which database should the shop use?"}]')" \
  "leaves a window holding several questions to the one-question gate"
drop_store

new_store
printf 'not json\n' > "$SYMPHONY_REPO_ANSWERS_DIR/shop.json"
assert_equals "|0" "$(ask "$SETTLED" 2>/dev/null; printf '|%s' "$?")" \
  "lets a question through when the search fails"
drop_store

new_store
printf 'not json\n' > "$SYMPHONY_REPO_ANSWERS_DIR/shop.json"
assert_equals "answer-gate.sh: the saved answers search failed, so the question was asked unchecked" \
  "$(ask "$SETTLED" 2>&1 >/dev/null)" \
  "warns in one line when the search fails"
drop_store

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
