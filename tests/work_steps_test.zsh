#!/usr/bin/env zsh
# Tests for the pipeline's fixed steps: bin/work-start.sh, bin/work-check.sh,
# bin/work-push.sh and bin/work-finish.sh. Every case runs against a throwaway
# origin and main clone, a stub worktree-databases.sh and a stub gh, so no real
# repo, database or pull request is touched.
#
# Usage: zsh tests/work_steps_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
BIN="$SCRIPT_DIR/../bin"

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

setup() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/work_steps_test.XXXXXX")"
  BASE="${BASE:A}"
  git init -q --bare -b main "$BASE/origin.git"
  git clone -q "$BASE/origin.git" "$BASE/quotes" 2>/dev/null
  git -C "$BASE/quotes" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$BASE/quotes" push -q origin main
  MAIN="$BASE/quotes"
  mkdir -p "$BASE/stubs"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/databases"\n' "$BASE" > "$BASE/stubs/worktree-databases.sh"
  chmod +x "$BASE/stubs/worktree-databases.sh"
  export SYMPHONY_WORKTREE_DATABASES="$BASE/stubs/worktree-databases.sh"
  export WORK_ITEM_ID=7
  checks '[]'
  cd "$MAIN"
}

teardown() {
  cd "$SCRIPT_DIR"
  rm -rf "$BASE"
  unset SYMPHONY_WORKTREE_DATABASES WORK_ITEM_ID PIPELINE_STEP
}

checks() {
  export PIPELINE_STEP="$(jq -nc --argjson checks "$1" --arg title "${2:-Export quotes}" \
    '{id: "start", kind: "script", work: {title: $title, repo: "acme/quotes"}, checks: $checks}')"
}

pull_request() {
  printf '#!/usr/bin/env bash\necho %s\n' "${(q)1}" > "$BASE/stubs/gh"
  chmod +x "$BASE/stubs/gh"
  path=("$BASE/stubs" $path)
}

entry() {
  jq -nc --arg kind "$1" --arg name "$2" --arg check "$3" --arg fix "${4:-}" --arg instruction "${5:-}" \
    '{kind: $kind, name: $name, purpose: "", check_command: $check, fix_command: $fix, instruction: $instruction}'
}

setup
"$BIN/work-start.sh" >/dev/null 2>&1
assert_equals "$BASE/quotes-7-export-quotes 7-export-quotes" "$(git -C "$MAIN" worktree list --porcelain | awk '/^worktree / { tree = $2 } /^branch / { sub("refs/heads/", "", $2); if ($2 != "main") print tree, $2 }')" \
  "the start step makes the work item's worktree beside the main clone, on a branch that begins with its id"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
assert_equals "create $BASE/quotes-7-export-quotes" "$(cat "$BASE/databases")" "the start step creates the worktree's databases"
teardown

setup
checks "[$(entry setup ready 'test -f ready.flag' 'touch ready.flag')]"
"$BIN/work-start.sh" >/dev/null 2>&1
outcome=$?
assert_equals "0 yes" "$outcome $([ -f "$BASE/quotes-7-export-quotes/ready.flag" ] && echo yes || echo no)" \
  "the start step runs a setup entry's fix command in the worktree when its check fails"
teardown

setup
checks "[$(entry setup postgres 'false' 'true' 'Start Postgres with brew services start postgresql')]"
output=$("$BIN/work-start.sh" 2>&1)
outcome=$?
assert_equals "1 Start Postgres with brew services start postgresql" "$outcome $(printf '%s\n' "$output" | tail -1)" \
  "the start step shows a setup entry's instruction and fails when its check still fails"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
WORK_ITEM_ID=8 checks '[]' 'Import prices'
WORK_ITEM_ID=8 "$BIN/work-start.sh" >/dev/null 2>&1
assert_equals "7-export-quotes 8-import-prices" "$(git -C "$MAIN" branch --format='%(refname:short)' | grep -v '^main$' | tr '\n' ' ' | sed 's/ $//')" \
  "two work items in the same repo get two worktrees and two branches"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
output=$("$BIN/work-start.sh" 2>&1)
assert_equals "Worktree already at $BASE/quotes-7-export-quotes
2" "$(printf '%s\n' "$output" | head -1)
$(git -C "$MAIN" worktree list | wc -l | tr -d ' ')" \
  "the start step reports a work item's existing worktree and makes no second one"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
checks "[$(entry test suite 'true'), $(entry lint style 'true')]"
"$BIN/work-check.sh" >/dev/null 2>&1
passed=$?
checks "[$(entry test suite 'true'), $(entry lint style 'exit 2')]"
"$BIN/work-check.sh" >/dev/null 2>&1
assert_equals "0 1" "$passed $?" "the check step passes only when every test and lint entry exits zero"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
checks "[$(entry test suite 'true')]"
output=$("$BIN/work-check.sh" 2>&1)
assert_equals "1 No lint entry for acme/quotes" "$? $output" "the check step fails, naming the missing kind, for a repo with no lint entry"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
checks "[$(entry test suite 'exit 3'), $(entry lint style 'true')]"
assert_equals "suite: exit 3
style: exit 0" "$("$BIN/work-check.sh" 2>&1 | grep ': exit ')" "the check step's output carries each command's exit status"
teardown

setup
checks "[$(entry setup ready 'true'), $(entry test suite 'true'), $(entry lint style 'true')]"
"$BIN/work-start.sh" >/dev/null 2>&1
"$BIN/work-check.sh" >/dev/null 2>&1
assert_equals "" "$(git -C "$BASE/quotes-7-export-quotes" status --porcelain)" "no step adds or changes a file in the repo to hold its commands"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
git -C "$BASE/quotes-7-export-quotes" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "Export quotes"
checks "[$(entry test suite 'true'), $(entry lint style 'true')]"
"$BIN/work-push.sh" >/dev/null 2>&1
assert_equals "0 Export quotes" "$? $(git -C "$BASE/origin.git" log -1 --format=%s 7-export-quotes 2>/dev/null)" "the push step pushes the branch when the test and lint entries pass and nothing is uncommitted"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
touch "$BASE/quotes-7-export-quotes/unsaved.rb"
checks "[$(entry test suite 'true'), $(entry lint style 'true')]"
output=$("$BIN/work-push.sh" 2>&1)
assert_equals "1 Something is uncommitted in $BASE/quotes-7-export-quotes
no branch" "$? $(printf '%s\n' "$output" | tail -1)
$(git -C "$BASE/origin.git" rev-parse -q --verify 7-export-quotes >/dev/null && echo pushed || echo no branch)" "the push step refuses to push while something is uncommitted"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
checks "[$(entry test suite 'exit 1'), $(entry lint style 'true')]"
"$BIN/work-push.sh" >/dev/null 2>&1
assert_equals "1 no branch" "$? $(git -C "$BASE/origin.git" rev-parse -q --verify 7-export-quotes >/dev/null && echo pushed || echo no branch)" "the push step refuses to push when a test or lint entry fails"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
pull_request '{"state":"OPEN"}'
output=$("$BIN/work-finish.sh" 2>&1)
assert_equals "1 The pull request for 7-export-quotes is not merged
kept" "$? $output
$([ -d "$BASE/quotes-7-export-quotes" ] && echo kept || echo removed)" "the finish step fails, changing nothing, while the branch's pull request is not merged"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
pull_request '{"state":"MERGED"}'
"$BIN/work-finish.sh" >/dev/null 2>&1
assert_equals "0 removed " "$? $([ -d "$BASE/quotes-7-export-quotes" ] && echo kept || echo removed) $(git -C "$MAIN" branch --list '7-*')" "the finish step removes the worktree and its branch once the pull request is merged"
teardown

setup
"$BIN/work-start.sh" >/dev/null 2>&1
touch "$BASE/quotes-7-export-quotes/.decisions.md" "$BASE/quotes-7-export-quotes/.ticket" "$BASE/quotes-7-export-quotes/start_here.md"
pull_request '{"state":"MERGED"}'
"$BIN/work-finish.sh" >/dev/null 2>&1
assert_equals "0 removed" "$? $([ -d "$BASE/quotes-7-export-quotes" ] && echo kept || echo removed)" "the finish step removes the worktree's decision log, ticket and resume bookmark too"
teardown

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
