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

# A repo of acme/widget on branch $1, a cache directory, and a gh where task 12
# sits under plan 7, "Quote builder", with 3 of 8 units closed.
new_repo() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/status_line_test.XXXXXX")"
  REPO="$WORK/widget"
  git init -q -b "$1" "$REPO"
  git -C "$REPO" remote add origin git@github.com:acme/widget.git
  export STATUS_LINE_DIR="$WORK/cache"
  export OWNER_TURN_DIR="$WORK/owner-turn"
  export WORKING_LINE_DIR="$WORK/working-line"
  export AGENT_PROGRESS_DIR="$WORK/agent-progress"
  export AGENT_PROGRESS_AGENTS="$WORK/agents"
  GH_LOG="$WORK/calls"
  : > "$GH_LOG"
  COUNTS="$WORK/counts"
  printf '3\t8' > "$COUNTS"
  UNITS="$WORK/units"
  printf '[]' > "$UNITS"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
case "\$*" in
  "api repos/acme/widget/issues/12/parent --jq "*)
    printf '7\tQuote builder\t%s\n' "\$(cat "$COUNTS")" ;;
  "api repos/acme/widget/issues/7/sub_issues --paginate")
    cat "$UNITS" ;;
  "api repos/acme/widget/issues/12 --jq .body")
    printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n' ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
STUB
  chmod +x "$WORK/bin/gh"
  path=("$WORK/bin" $path)
}

drop_repo() {
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
  unset STATUS_LINE_DIR OWNER_TURN_DIR WORKING_LINE_DIR AGENT_PROGRESS_DIR AGENT_PROGRESS_AGENTS
}

status_line() {
  jq -nc --arg dir "$REPO" '{session_id: "s1", workspace: {current_dir: $dir}}' | "$STATUS_LINE" 2>&1
}

echo "status-line.sh:"

new_repo 12-quote-lines
assert_equals $'Quote builder · stage 2 of 4 — Enrich\n███░░░░░░░ 3/8' "$(status_line)" \
  "shows the plan's title and the task's stage above a bar and the closed units out of all units"
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
printf '4\t8' > "$COUNTS"
assert_equals $'Quote builder · stage 2 of 4 — Enrich\n█████░░░░░ 4/8' "$(STATUS_LINE_NOW=1060 status_line)" \
  "shows a closed unit in the count a minute after the last read"
drop_repo

new_repo 12-quote-lines
jq -nc --arg cwd "$REPO" \
  '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Which road?"}]}}' \
  | "$SCRIPT_DIR/../bin/owner-turn.sh" record
assert_equals $'▶ question · Which road?\nQuote builder · stage 2 of 4 — Enrich\n███░░░░░░░ 3/8' "$(status_line)" \
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
assert_equals $'● working · Run every test suite\nQuote builder · stage 2 of 4 — Enrich\n███░░░░░░░ 3/8' "$(status_line)" \
  "shows the working line on top while the session works"
drop_repo

new_repo 12-quote-lines
jq -nc '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Agent", tool_input: {description: "Review PR #142"}}' \
  | "$SCRIPT_DIR/../bin/working-line.sh" record
mkdir -p "$AGENT_PROGRESS_DIR" "$AGENT_PROGRESS_AGENTS"
for n in {1..11}; do printf '%d. **Step %d.** Do it.\n' $n $n; done > "$AGENT_PROGRESS_AGENTS/review-scribe.md"
printf '1000\treview-scribe\tacme/widget#142\t3. Run every check\ts1\n' > "$AGENT_PROGRESS_DIR/a1.log"
assert_equals $'● working · Review PR #142\nreview-scribe acme/widget#142\n█░░░░░░░░░ 3/11 · Run every check\nQuote builder · stage 2 of 4 — Enrich\n███░░░░░░░ 3/8' "$(status_line)" \
  "shows each running agent's lines under the working line"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
