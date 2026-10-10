#!/usr/bin/env zsh
# Tests for bin/status-line.sh. Every case runs in a throwaway repo with its own
# cache directory, against a stub gh that writes down its calls.
#
# Usage: zsh tests/status_line_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STATUS_LINE="$SCRIPT_DIR/../bin/status-line.sh"

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

GREEN=$'\e[32m■\e[0m'
YELLOW=$'\e[33m■\e[0m'
GREY=$'\e[90m■\e[0m'
SQUARES="$GREEN$YELLOW$GREY$GREY"

unit() {
  jq -nc --arg state "$1" --arg stage "$2" '{state: $state, body: ("## Part of\nQuote building, " + $stage + ".\n")}'
}

# A repo of acme/widget on branch $1, a cache directory, and a gh where task 12
# sits under plan 7, "Quote builder", with 3 of 8 units closed: both of stage 1,
# one of stage 2's three, none of stage 3's one and none of stage 4's two.
GH_STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/status_line_stub.XXXXXX")"
GH_STUB="$GH_STUB_DIR/gh"
cat > "$GH_STUB" <<'STUB'
#!/usr/bin/env bash
work="$STATUS_LINE_TEST_WORK"
printf '%s\n' "$*" >> "$work/calls"
[ ! -f "$work/offline" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
[ ! -f "$work/hang" ] || /bin/sleep 10
[ ! -f "$work/slow" ] || /bin/sleep 0.1
case "$*" in
  "api repos/acme/widget/issues/12/parent --jq "*)
    printf '7\tQuote builder\t%s\n' "$(cat "$work/counts")" ;;
  "api repos/acme/widget/issues/7/sub_issues --paginate")
    cat "$work/units" ;;
  "api repos/acme/plans/issues/7/sub_issues --paginate")
    cat "$work/units" ;;
  "api repos/acme/widget/issues/12 --jq .body")
    cat "$work/task-body" ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH_STUB"
STATUS_LINE_TEST_WORK=/nonexistent "$GH_STUB" >/dev/null 2>&1

new_repo() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/status_line_test.XXXXXX")"
  export STATUS_LINE_TEST_WORK="$WORK"
  REPO="$WORK/widget"
  git init -q --template= -b "$1" "$REPO"
  git -C "$REPO" remote add origin git@github.com:acme/widget.git
  export STATUS_LINE_DIR="$WORK/cache"
  export STATUS_LINE_LIMIT=30
  export OWNER_TURN_DIR="$WORK/owner-turn"
  export WORKING_LINE_DIR="$WORK/working-line"
  export AGENT_PROGRESS_DIR="$WORK/agent-progress"
  export AGENT_PROGRESS_AGENTS="$WORK/agents"
  GH_LOG="$WORK/calls"
  : > "$GH_LOG"
  COUNTS="$WORK/counts"
  printf '3\t8' > "$COUNTS"
  TASK_BODY="$WORK/task-body"
  printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n' > "$TASK_BODY"
  UNITS="$WORK/units"
  {
    unit closed "stage 1 of 4 — End to end"
    unit closed "stage 1 of 4 — End to end"
    unit closed "stage 2 of 4 — Enrich"
    unit open "stage 2 of 4 — Enrich"
    unit open "stage 2 of 4 — Enrich"
    unit open "stage 3 of 4 — Simplify"
    unit open "stage 4 of 4 — Harden"
    unit open "stage 4 of 4 — Harden"
  } | jq -sc . > "$UNITS"
  mkdir -p "$WORK/bin"
  ln -s "$GH_STUB" "$WORK/bin/gh"
  path=("$WORK/bin" $path)
}

drop_repo() {
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
  unset STATUS_LINE_TEST_WORK STATUS_LINE_DIR STATUS_LINE_LIMIT OWNER_TURN_DIR WORKING_LINE_DIR AGENT_PROGRESS_DIR AGENT_PROGRESS_AGENTS
}

status_line() {
  jq -nc --arg dir "$REPO" '{session_id: "s1", workspace: {current_dir: $dir}}' | "$STATUS_LINE" 2>&1
}

echo "status-line.sh:"

new_repo 12-quote-lines
assert_equals $'Quote builder · stage 2 of 4 — Enrich\n'"$SQUARES 3/8" "$(status_line)" \
  "shows the plan's title and the task's stage above the stage squares and the closed units out of all units"
drop_repo

new_repo 12-quote-lines
assert_equals "■■■■ 3/8" "$(status_line | sed -n 2p | sed $'s/\e\\[[0-9;]*m//g')" \
  "shows one square per stage of the plan beside the closed units out of all units"
drop_repo

new_repo 12-quote-lines
{ unit closed "stage 1 of 1 — End to end"; unit closed "stage 1 of 1 — End to end"; } | jq -sc . > "$UNITS"
assert_equals "$GREEN 3/8" "$(status_line | sed -n 2p)" \
  "shows a stage's square green when every unit of that stage is closed"
drop_repo

new_repo 12-quote-lines
{ unit closed "stage 1 of 1 — End to end"; unit open "stage 1 of 1 — End to end"; } | jq -sc . > "$UNITS"
assert_equals "$YELLOW 3/8" "$(status_line | sed -n 2p)" \
  "shows a stage's square yellow when some but not all units of that stage are closed"
drop_repo

new_repo 12-quote-lines
{ unit open "stage 1 of 1 — End to end"; unit open "stage 1 of 1 — End to end"; } | jq -sc . > "$UNITS"
assert_equals "$GREY 3/8" "$(status_line | sed -n 2p)" \
  "shows a stage's square grey when no unit of that stage is closed"
drop_repo

new_repo feature/quote-lines
assert_equals "" "$(status_line)" "shows no plan progress on a branch whose name has no leading issue number"
drop_repo

new_repo 13-loose-task
assert_equals "" "$(status_line)" "shows no plan progress on a branch whose issue is listed under no plan"
drop_repo

new_repo 12-quote-lines
STATUS_LINE_NOW=1000 status_line >/dev/null
STATUS_LINE_NOW=1059 status_line >/dev/null
assert_equals "1" "$(grep -c '/parent' "$GH_LOG")" \
  "asks GitHub once for refreshes within the same minute"
drop_repo

new_repo 12-quote-lines
STATUS_LINE_NOW=1000 status_line >/dev/null
STATUS_LINE_NOW=1059 status_line >/dev/null
assert_equals "1" "$(grep -c '/sub_issues' "$GH_LOG")" \
  "asks GitHub once for the stage counts for refreshes within the same minute"
drop_repo

new_repo 12-quote-lines
STATUS_LINE_NOW=1000 status_line >/dev/null
printf '4\t8' > "$COUNTS"
assert_equals $'Quote builder · stage 2 of 4 — Enrich\n'"$SQUARES 4/8" "$(STATUS_LINE_NOW=1060 status_line)" \
  "shows a closed unit in the count a minute after the last read"
drop_repo

new_repo 12-quote-lines
jq -nc --arg cwd "$REPO" \
  '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Which road?"}]}}' \
  | "$SCRIPT_DIR/../bin/owner-turn.sh" record
assert_equals $'▶ question · Which road?\nQuote builder · stage 2 of 4 — Enrich\n'"$SQUARES 3/8" "$(status_line)" \
  "shows the session's flag on its own line above the plan progress"
drop_repo

new_repo main
jq -nc --arg cwd "$REPO" \
  '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Which road?"}]}}' \
  | "$SCRIPT_DIR/../bin/owner-turn.sh" record
assert_equals "▶ question · Which road?" "$(status_line)" "shows the session's flag on a branch with no plan"
drop_repo

new_repo 12-quote-lines
jq -nc '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", tool_input: {command: "true", description: "Run every test suite"}}' \
  | "$SCRIPT_DIR/../bin/working-line.sh" record
assert_equals $'● working · Run every test suite\nQuote builder · stage 2 of 4 — Enrich\n'"$SQUARES 3/8" "$(status_line)" \
  "shows the working line on top while the session works"
drop_repo

new_repo 12-quote-lines
jq -nc '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Agent", tool_input: {description: "Review PR #142"}}' \
  | "$SCRIPT_DIR/../bin/working-line.sh" record
mkdir -p "$AGENT_PROGRESS_DIR" "$AGENT_PROGRESS_AGENTS"
for n in {1..11}; do printf '%d. **Step %d.** Do it.\n' $n $n; done > "$AGENT_PROGRESS_AGENTS/review-scribe.md"
printf '1000\treview-scribe\tacme/widget#142\t3. Run every check\ts1\n' > "$AGENT_PROGRESS_DIR/a1.log"
assert_equals $'● working · Review PR #142\nreview-scribe acme/widget#142\n█░░░░░░░░░ 3/11 · Run every check\nQuote builder · stage 2 of 4 — Enrich\n'"$SQUARES 3/8" "$(status_line)" \
  "shows each running agent's lines under the working line"
drop_repo

new_repo 12-quote-lines
printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n\n## Acceptance criteria\n- [x] A rep can quote.\n- [ ] A rep can save.\n- [ ] A rep can send.\n- [ ] A rep can print.\n' > "$TASK_BODY"
assert_equals "██░░░░░░░░ 1/4 criteria" "$(status_line | tail -1)" \
  "shows a second bar of the task's ticked acceptance criteria out of all of them"
drop_repo

new_repo 12-quote-lines
printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n\n## Acceptance criteria\n- [x] A rep can quote.\n- [ ] A rep can save.\n' > "$TASK_BODY"
STATUS_LINE_NOW=1000 status_line >/dev/null
printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n\n## Acceptance criteria\n- [x] A rep can quote.\n- [x] A rep can save.\n' > "$TASK_BODY"
assert_equals "██████████ 2/2 criteria" "$(STATUS_LINE_NOW=1060 status_line | tail -1)" \
  "shows a newly ticked criterion in the second bar a minute after the last read"
drop_repo

new_repo 12-quote-lines
printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n\n## Acceptance criteria\n- [x] A rep can quote.\n- [ ] A rep can save.\n' > "$TASK_BODY"
assert_equals $'\e[32m■\e[0m\e[33m■\e[0m\e[90m■\e[0m\e[90m■\e[0m 3/8\n█████░░░░░ 1/2 criteria' "$(status_line | tail -2)" \
  "shows the plan bar and the criteria bar on their own lines"
drop_repo

new_repo 12-quote-lines
assert_equals $'\e[32m■\e[0m\e[33m■\e[0m\e[90m■\e[0m\e[90m■\e[0m 3/8' "$(status_line | tail -1)" \
  "shows only the plan bar for a task with no acceptance criteria"
drop_repo

new_repo 12-quote-lines
STATUS_LINE_NOW=1000 status_line >/dev/null
touch "$WORK/offline"
assert_equals $'\e[32m■\e[0m\e[33m■\e[0m\e[90m■\e[0m\e[90m■\e[0m 3/8 · out of date' "$(STATUS_LINE_NOW=1060 status_line | tail -1)" \
  "shows the last count it read, marked out of date, when GitHub cannot be read"
drop_repo

new_repo 12-quote-lines
touch "$WORK/offline"
assert_equals "Plan progress unavailable: GitHub cannot be read" "$(status_line)" \
  "says progress is unavailable when GitHub cannot be read and no count was ever read"
drop_repo

zmodload zsh/datetime
new_repo 12-quote-lines
touch "$WORK/hang"
unset STATUS_LINE_LIMIT
started=$EPOCHREALTIME
status_line >/dev/null
assert_equals "1" "$(( EPOCHREALTIME - started < 2 ))" "prints within two seconds when GitHub does not answer"
drop_repo

new_repo 12-quote-lines
touch "$WORK/slow"
assert_equals "Plan progress unavailable: GitHub cannot be read" "$(STATUS_LINE_LIMIT=0.05 status_line)" \
  "waits on GitHub only as long as its limit setting allows"
drop_repo

new_repo 12-quote-lines
printf '3\t8\tacme/plans' > "$COUNTS"
assert_equals $'Quote builder · stage 2 of 4 — Enrich\n\e[32m■\e[0m\e[33m■\e[0m\e[90m■\e[0m\e[90m■\e[0m 3/8' "$(status_line)" \
  "shows the plan's progress on the branch of a task whose plan lives in another repo"
drop_repo

rm -rf "$GH_STUB_DIR"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
