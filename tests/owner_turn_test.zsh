#!/usr/bin/env zsh
# Tests for bin/owner-turn.sh. Every case writes its record into a throwaway
# directory, so no real record is touched.
#
# Usage: zsh tests/owner_turn_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
TURN="$SCRIPT_DIR/../bin/owner-turn.sh"

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

echo "owner-turn.sh:"

output=$("$TURN" "lunch" "Eat something" 2>&1)
code=$?
assert_equals "64 owner-turn.sh: the kind is one of permission, question, pull request or plan" "$code $output" \
  "refuses a kind that is not one of the four, naming them"

# A repo of acme/widget and an empty record, both thrown away by drop_record.
new_record() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/owner_turn_test.XXXXXX")"
  REPO="$WORK/widget"
  git init -q "$REPO"
  git -C "$REPO" remote add origin git@github.com:acme/widget.git
  export OWNER_TURN_DIR="$WORK/record"
}

drop_record() {
  rm -rf "$WORK"
  unset OWNER_TURN_DIR
}

record_bash() {
  jq -nc --arg session "$1" --arg cwd "$REPO" --arg command "$2" \
    '{hook_event_name: "PreToolUse", session_id: $session, cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' \
    | OWNER_TURN_NOW="${3:-1000}" "$TURN" record
}

entries() {
  local files=("$OWNER_TURN_DIR"/entries/*.json(N))
  if (( $#files )); then jq -sc 'sort_by(.arrived)' $files; else echo '[]'; fi
}

echo ""
echo "owner-turn.sh record:"

new_record
record_bash s1 '~/.claude/bin/owner-turn.sh "plan" "Review plan #110" "https://github.com/acme/widget/issues/110"'
assert_equals '[{"kind":"plan","wanted":"Review plan #110","link":"https://github.com/acme/widget/issues/110","session":"s1","repo":"acme/widget","arrived":1000}]' \
  "$(entries)" "records an entry with its kind, what is wanted, its link, the session, the repo and when it arrived"
drop_record

new_record
jq -nc --arg cwd "$REPO" \
  '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Which road?"}]}}' \
  | OWNER_TURN_NOW=1000 "$TURN" record
assert_equals '[{"kind":"question","wanted":"Which road?","link":"","session":"s1","repo":"acme/widget","arrived":1000}]' \
  "$(entries)" "records a question entry when a session asks the owner a question"
drop_record

new_record
record_bash s1 '~/.claude/bin/owner-turn.sh "plan" "Review plan #110"'
record_bash s1 '~/.claude/bin/owner-turn.sh "pull request" "Review PR #135"'
assert_equals "2" "$(entries | jq length)" "records two items waiting in one session as two entries"
drop_record

echo ""
echo "owner-turn.sh flags:"

new_record
record_bash s1 '~/.claude/bin/owner-turn.sh "plan" "Review plan #110" "https://github.com/acme/widget/issues/110"'
assert_equals "▶ plan · Review plan #110 · https://github.com/acme/widget/issues/110" "$("$TURN" flags s1)" \
  "shows a marker, the kind, what is wanted and the link for an entry the session is waiting on"
drop_record

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
