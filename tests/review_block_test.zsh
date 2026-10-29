#!/usr/bin/env zsh
setopt no_unset
zmodload zsh/datetime

SCRIPT_DIR="${0:A:h}"
BLOCK="$SCRIPT_DIR/../bin/review-block.sh"

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

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

new_state() {
  STATE="$(mktemp -d "${TMPDIR:-/tmp}/review_block_test.XXXXXX")"
  export CLAUDE_REVIEW_BLOCK_DIR="$STATE/marks"
  REPO="/work/shop"
}

drop_state() {
  rm -rf "$STATE"
  unset CLAUDE_REVIEW_BLOCK_DIR
}

start() {
  jq -nc --arg type "${2:-review-scribe}" --arg prompt "Repo: acme/shop, PR 12, job: review" \
    '{session_id: $ARGS.positional[0], tool_name: "Agent", tool_input: {subagent_type: $type, prompt: $prompt}}' \
    --args "$1" | "$BLOCK" start
}

marks() { ls "$CLAUDE_REVIEW_BLOCK_DIR" 2>/dev/null | wc -l | tr -d ' '; }

echo "review-block.sh start:"

new_state
start s1 >/dev/null
assert_equals "1" "$(marks)" "marks the session as reviewing when it spawns the review scribe"
drop_state

new_state
start s1 pr-scribe >/dev/null
assert_equals "0" "$(marks)" "marks nothing when the session spawns any other agent"
drop_state

edit() {
  jq -nc --arg tool "$1" --arg path "$2" --arg session "${3:-s1}" \
    '{session_id: $session, tool_name: $tool, tool_input: {file_path: $path}}' | "$BLOCK" check
}

echo "review-block.sh check:"

new_state
start s1 >/dev/null
assert_contains '"permissionDecision":"deny"' "$(edit Edit "$REPO/app/models/quote.rb")" \
  "refuses an edit to a file in the repo while the session is reviewing"
drop_state

new_state
start s1 >/dev/null
assert_equals "" "$(edit Edit "$REPO/app/models/quote.rb" s2)" \
  "lets another session edit while one session is reviewing"
drop_state

new_state
start s1 >/dev/null
assert_equals "" "$(edit Write "$STATE/scratchpad/notes.md")" \
  "lets the reviewing session write in a temporary folder"
drop_state

new_state
start s1 >/dev/null
assert_equals "" "$(edit Write "$REPO/.review-12.claims.json")" \
  "lets the reviewing session write the review draft and the files beside it"
drop_state

new_state
start s1 >/dev/null
assert_equals "" \
  "$(jq -nc --arg path "$STATE/scratchpad/look.ipynb" '{session_id: "s1", tool_name: "NotebookEdit", tool_input: {notebook_path: $path}}' | "$BLOCK" check)" \
  "reads a notebook edit's path, letting one in a temporary folder through"
drop_state

run() {
  jq -nc --arg cmd "$1" --arg cwd "$REPO" '{session_id: "s1", tool_name: "Bash", cwd: $cwd, tool_input: {command: $cmd}}' \
    | "$BLOCK" check
}

refused() {
  local command count=0
  for command in "$@"; do
    [[ "$(run "$command")" == *'"permissionDecision":"deny"'* ]] && count=$((count+1))
  done
  printf '%s' "$count"
}

new_state
start s1 >/dev/null
assert_equals "0" "$(refused 'git status' 'git log --oneline -5' 'gh pr diff 12' 'cat app/models/quote.rb')" \
  "lets the reviewing session run commands that only read"
drop_state

new_state
start s1 >/dev/null
assert_equals "6" "$(refused 'git commit -m "Fix the loop"' 'git push origin HEAD' 'git merge main' \
    'git rebase main' 'cd /work/shop && git reset --hard' 'git -C /work/shop commit -am wip')" \
  "refuses each git command that commits, pushes, merges, rebases or resets"
drop_state

new_state
start s1 >/dev/null
assert_equals "8" "$(refused 'bin/rails test test/models/quote_test.rb' 'bundle exec rspec spec/quote_spec.rb' \
    'rspec' 'bun test' 'npm test' 'yarn test' 'pnpm test' 'cd /work/shop && ./run_tests.sh')" \
  "refuses each run of the repo's tests"
drop_state

new_state
start s1 >/dev/null
assert_equals "0" "$(refused "echo 'done; git commit'" 'grep -n "x && npm test" README.md')" \
  "lets through a command that only names a git command or a test run in quoted text"
drop_state

new_state
start s1 >/dev/null
touch -t "$(strftime %Y%m%d%H%M.%S $(( EPOCHSECONDS - 90000 )))" "$CLAUDE_REVIEW_BLOCK_DIR"/*
assert_equals "" "$(edit Edit "$REPO/app/models/quote.rb")" \
  "ignores a review mark set more than a day ago"
drop_state

new_state
start s1 >/dev/null
reason=$(edit Edit "$REPO/app/models/quote.rb" | jq -r '.hookSpecificOutput.permissionDecisionReason')
assert_contains "post the review with ~/.claude/bin/review-draft.sh --post or drop it with ~/.claude/bin/review-block.sh drop first" \
  "$reason" "the refusal says to post or drop the review before making a fix the owner asked for"
drop_state

new_state
start s1 >/dev/null
reason=$(run 'git commit -m wip' | jq -r '.hookSpecificOutput.permissionDecisionReason')
assert_contains ", so it only reads code and writes the review." \
  "$reason" "the refusal says the session is reviewing and only reads code and writes the review"
drop_state

new_state
start s1 >/dev/null
assert_equals "acme/shop#12" "$(cat "$CLAUDE_REVIEW_BLOCK_DIR"/*)" \
  "records which pull request the session is reviewing, read from what the scribe was asked"
drop_state

new_state
start s1 >/dev/null
reason=$(run 'bun test' | jq -r '.hookSpecificOutput.permissionDecisionReason')
assert_contains "This session is reviewing acme/shop#12," "$reason" \
  "the refusal names the pull request the session is reviewing"
drop_state

ran() {
  jq -nc --arg cmd "$1" '{session_id: "s1", tool_name: "Bash", tool_input: {command: $cmd}}' | "$BLOCK" clear
}

echo "review-block.sh clear:"

new_state
start s1 >/dev/null
ran '~/.claude/bin/review-draft.sh --post acme/shop 12 /work/shop/.review-12.json' >/dev/null
assert_equals "0" "$(marks)" "clears the review mark once the session posts the review"
drop_state

echo "the hooks in hooks.json:"

assert_equals "\${CLAUDE_PLUGIN_ROOT}/bin/review-block.sh start" \
  "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Agent") | .hooks[].command | select(test("review-block"))' "$SCRIPT_DIR/../hooks/hooks.json")" \
  "the hooks send each spawned agent to the review mark"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
