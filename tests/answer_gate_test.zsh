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

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
