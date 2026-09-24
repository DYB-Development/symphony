#!/usr/bin/env zsh
# Tests for bin/usage.sh. Every case runs inside a throwaway git repo with a
# throwaway Claude config directory, so no real transcript is ever read.
#
# Usage: zsh tests/usage_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
USAGE="$SCRIPT_DIR/../bin/usage.sh"

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

new_repo() {
  REPO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/usage_test.XXXXXX")" && pwd -P)"
  git -C "$REPO" init -q
  git -C "$REPO" symbolic-ref HEAD refs/heads/main
  export CLAUDE_CONFIG_DIR="$REPO/config"
  TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/a-repo/session.jsonl"
  mkdir -p "${TRANSCRIPT:h}"
  : > "$TRANSCRIPT"
  cd "$REPO"
}

drop_repo() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
  unset CLAUDE_CONFIG_DIR
}

entry() {
  local id="$1" branch="$2" cwd="$3" input="$4" output="$5" read="$6" write="$7"
  jq -nc --arg id "$id" --arg branch "$branch" --arg cwd "$cwd" \
    --argjson input "$input" --argjson output "$output" \
    --argjson read "$read" --argjson write "$write" \
    '{type: "assistant", gitBranch: $branch, cwd: $cwd, message: {id: $id, usage: {
      input_tokens: $input,
      output_tokens: $output,
      cache_read_input_tokens: $read,
      cache_creation_input_tokens: $write
    }}}' >> "$TRANSCRIPT"
}

agent_entry() {
  local agent="$1" type="$2" id="$3" branch="$4" cwd="$5" input="$6" output="$7" read="$8" write="$9"
  local stamp="${10:-}"
  jq -nc --arg agent "$agent" --arg type "$type" --arg id "$id" --arg branch "$branch" \
    --arg cwd "$cwd" --argjson input "$input" --argjson output "$output" \
    --argjson read "$read" --argjson write "$write" --arg stamp "$stamp" \
    '{type: "assistant", agentId: $agent, attributionAgent: $type, timestamp: $stamp, gitBranch: $branch, cwd: $cwd,
      message: {id: $id, usage: {
        input_tokens: $input,
        output_tokens: $output,
        cache_read_input_tokens: $read,
        cache_creation_input_tokens: $write
      }}}' >> "$TRANSCRIPT"
}

commit_at() {
  local at="$1"
  GIT_COMMITTER_DATE="$at" GIT_AUTHOR_DATE="$at" \
    git -C "$REPO" -c user.name=t -c user.email=t@example.com \
    commit -q --allow-empty -m "work"
}

checkout_at() {
  local at="$1"
  shift
  GIT_COMMITTER_DATE="$at" git -C "$REPO" checkout -q "$@"
}

entry_at() {
  local id="$1" branch="$2" cwd="$3" at="$4" input="$5" output="$6" read="$7" write="$8"
  jq -nc --arg id "$id" --arg branch "$branch" --arg cwd "$cwd" --arg at "$at" \
    --argjson input "$input" --argjson output "$output" \
    --argjson read "$read" --argjson write "$write" \
    '{type: "assistant", gitBranch: $branch, cwd: $cwd, timestamp: $at, message: {id: $id, usage: {
      input_tokens: $input,
      output_tokens: $output,
      cache_read_input_tokens: $read,
      cache_creation_input_tokens: $write
    }}}' >> "$TRANSCRIPT"
}

worktree_at() {
  local at="$1" tree="$2" branch="$3"
  GIT_COMMITTER_DATE="$at" git -C "$REPO" worktree add -q -b "$branch" "$tree" >/dev/null
}

command_entry() {
  local id="$1" branch="$2" cwd="$3" at="$4" command="$5"
  local input="$6" output="$7" read="$8" write="$9"
  jq -nc --arg id "$id" --arg branch "$branch" --arg cwd "$cwd" --arg at "$at" \
    --arg command "$command" --argjson input "$input" --argjson output "$output" \
    --argjson read "$read" --argjson write "$write" \
    '{type: "assistant", gitBranch: $branch, cwd: $cwd, timestamp: $at, message: {id: $id,
      content: [{type: "tool_use", name: "Bash", input: {command: $command}}],
      usage: {
        input_tokens: $input,
        output_tokens: $output,
        cache_read_input_tokens: $read,
        cache_creation_input_tokens: $write
      }}}' >> "$TRANSCRIPT"
}

another_transcript() {
  TRANSCRIPT="${TRANSCRIPT:h}/$1.jsonl"
  : > "$TRANSCRIPT"
}

edit_entry() {
  local id="$1" cwd="$2" at="$3" file="$4"
  jq -nc --arg id "$id" --arg cwd "$cwd" --arg at "$at" --arg file "$file" \
    '{type: "user", cwd: $cwd, timestamp: $at, message: {id: $id},
      toolUseResult: {bashEditDiff: {files: [{filePath: $file}]}}}' >> "$TRANSCRIPT"
}

user_entry() {
  local uuid="$1" session="$2" cwd="$3" at="$4" content="$5"
  jq -nc --arg uuid "$uuid" --arg session "$session" --arg cwd "$cwd" --arg at "$at" \
    --argjson content "$content" \
    '{type: "user", uuid: $uuid, sessionId: $session, isSidechain: false, cwd: $cwd, timestamp: $at,
      message: {role: "user", content: $content}}' >> "$TRANSCRIPT"
}

result_entry() {
  local uuid="$1" session="$2" cwd="$3" at="$4" result="$5" content="$6"
  jq -nc --arg uuid "$uuid" --arg session "$session" --arg cwd "$cwd" --arg at "$at" \
    --argjson result "$result" --argjson content "$content" \
    '{type: "user", uuid: $uuid, sessionId: $session, isSidechain: false, cwd: $cwd, timestamp: $at,
      message: {role: "user", content: $content}, toolUseResult: $result}' >> "$TRANSCRIPT"
}

echo "usage.sh:"

new_repo
entry msg_1 main "$REPO" 2 321 24835 44814
assert_equals "Input: 2
Output: 321
Cache read: 24,835
Cache write: 44,814
Total: 69,972" "$("$USAGE")" "totals the tokens of one message on this branch"
drop_repo

new_repo
entry msg_1 main "$REPO" 2 321 24835 44814
entry msg_1 main "$REPO" 2 321 24835 44814
assert_equals "Input: 2
Output: 321
Cache read: 24,835
Cache write: 44,814
Total: 69,972" "$("$USAGE")" "counts a message written across two entries once"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
checkout_at 2026-01-03T00:00:00Z -b feature
entry_at msg_1 main "$REPO" 2026-01-02T00:00:00Z 1 1 1 1
assert_equals "No tokens recorded for this branch." "$("$USAGE")" \
  "leaves out a message recorded before this branch was checked out"

new_repo
entry msg_1 main "$REPO" 10 20 30 40
entry msg_2 main "${REPO}-elsewhere" 1 1 1 1
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "leaves out a message recorded in another repo"
drop_repo

new_repo
entry msg_1 main "$REPO/deep/nested" 10 20 30 40
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "counts a message recorded in a subdirectory of the repo"
drop_repo

new_repo
entry msg_1 main "$REPO" 2 321 24835 44814
assert_equals "## Tokens Used

- Input: 2
- Output: 321
- Cache read: 24,835
- Cache write: 44,814
- Total: 69,972" "$("$USAGE" --render)" "renders the section as a bullet per total"
drop_repo

new_repo
assert_equals "## Tokens Used

Not measured." "$("$USAGE" --render)" "renders Not measured when no transcript names this branch"
drop_repo

new_repo
"$USAGE" --everything >/dev/null 2>&1
assert_equals "64" "$?" "exits with a usage code when given an argument it does not take"
drop_repo

OUTSIDE="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/usage_test.XXXXXX")" && pwd -P)"
cd "$OUTSIDE"
"$USAGE" >/dev/null 2>&1
assert_equals "69" "$?" "exits with a no-input code outside a git repository"
cd "$SCRIPT_DIR"
rm -rf "$OUTSIDE"

new_repo
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$REPO" | tr -c 'a-zA-Z0-9' '-')/session.jsonl"
mkdir -p "${TRANSCRIPT:h}"
entry msg_1 main "$REPO" 10 20 30 40
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/another-repo/session.jsonl"
mkdir -p "${TRANSCRIPT:h}"
entry msg_2 main "$REPO" 1 1 1 1
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "reads only the project directory named for a repo whose path holds an underscore"
drop_repo

new_repo
agent_entry agent_1 pr-scribe msg_1 main "$REPO" 10 20 30 40
assert_equals "pr-scribe — main — 100" "$("$USAGE" --runs)" \
  "names a scribe run, the branch it ran on and what it cost"
drop_repo

new_repo
agent_entry agent_2 review-scribe msg_2 main "$REPO" 1 1 1 1 2026-02-02T00:00:00Z
agent_entry agent_1 pr-scribe msg_1 main "$REPO" 10 20 30 40 2026-01-01T00:00:00Z
assert_equals "pr-scribe — main — 100
review-scribe — main — 4" "$("$USAGE" --runs)" "lists the runs oldest first"
drop_repo

new_repo
agent_entry agent_1 pr-scribe msg_1 main "$REPO" 10 20 30 40
agent_entry agent_1 pr-scribe msg_1 main "$REPO" 10 20 30 40
assert_equals "pr-scribe — main — 100" "$("$USAGE" --runs)" \
  "counts a run's message written across two entries once"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
checkout_at 2026-01-03T00:00:00Z -b feature
agent_entry agent_1 review-scribe msg_1 main "$REPO" 10 20 30 40 2026-01-02T00:00:00Z
assert_equals "review-scribe — main — 100" "$("$USAGE" --runs)" \
  "names the branch a run worked on, not the branch checked out now"
drop_repo

new_repo
agent_entry agent_1 pr-scribe msg_1 main "${REPO}-elsewhere" 10 20 30 40
assert_equals "No scribe runs recorded for this repo." "$("$USAGE" --runs)" \
  "leaves out a run made in another repo"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
checkout_at 2026-01-02T00:00:00Z -b feature
entry_at msg_1 main "$REPO" 2026-01-03T00:00:00Z 10 20 30 40
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "counts a message by the branch the worktree held when it was recorded"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
worktree_at 2026-01-02T00:00:00Z "$REPO/trees/feature" feature
command_entry msg_1 main "$REPO" 2026-01-03T00:00:00Z \
  "cd $REPO/trees/feature && bin/rails test" 10 20 30 40
cd "$REPO/trees/feature"
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "counts a message whose command names the worktree holding this branch"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
worktree_at 2026-01-02T00:00:00Z "$REPO/trees/feature" feature
command_entry msg_1 main "$REPO" 2026-01-03T00:00:00Z \
  "cd $REPO/trees/feature && bin/rails test" 10 20 30 40
another_transcript alongside
command_entry msg_2 main "$REPO" 2026-01-03T00:00:01Z "cd $REPO && bin/rails test" 1 1 1 1
cd "$REPO/trees/feature"
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "leaves out a run working in another worktree at the same moment"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
worktree_at 2026-01-02T00:00:00Z "$REPO/trees/feature" feature
command_entry msg_1 main "$REPO" 2026-01-03T00:00:00Z \
  "cd $REPO/trees/feature && bin/rails test" 10 20 30 40
entry_at msg_2 main "$REPO" 2026-01-03T00:01:00Z 1 1 1 1
cd "$REPO/trees/feature"
assert_equals "Input: 11
Output: 21
Cache read: 31
Cache write: 41
Total: 104" "$("$USAGE")" "counts a later message in the run that named the worktree"
drop_repo

new_repo
commit_at 2026-01-01T00:00:00Z
worktree_at 2026-01-02T00:00:00Z "$REPO/trees/feature" feature
edit_entry result_1 "$REPO" 2026-01-03T00:00:00Z "$REPO/trees/feature/app/models/quote.rb"
entry_at msg_1 main "$REPO" 2026-01-03T00:01:00Z 10 20 30 40
cd "$REPO/trees/feature"
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "takes the worktree from a file the run changed"
drop_repo

new_repo
user_entry prompt_1 session_1 "$REPO" 2026-01-03T00:00:00Z '"fix it"'
assert_equals "1767398400	session_1	prompt	1" "$("$USAGE" --rows | grep '	prompt	')" "prints a row for a prompt typed on this branch"
drop_repo

new_repo
user_entry note_1 session_1 "$REPO" 2026-01-03T00:00:00Z '"<task-notification>\n<task-id>a1</task-id>\n</task-notification>"'
user_entry note_2 session_1 "$REPO" 2026-01-03T00:00:01Z '"Another Claude session sent a message:\n<agent-message from=\"a1\">done</agent-message>"'
user_entry note_3 session_1 "$REPO" 2026-01-03T00:00:02Z '"<local-command-stdout>ok</local-command-stdout>"'
user_entry note_4 session_1 "$REPO" 2026-01-03T00:00:03Z '"This session is being continued from a previous conversation that ran out of context."'
assert_equals "" "$("$USAGE" --rows | grep '	prompt	')" "prints no prompt row for a message Claude Code sent on its own"
drop_repo

new_repo
user_entry prompt_1 session_1 "$REPO" 2026-01-03T00:00:00Z '"fix the header please"'
assert_equals "1767398400	session_1	typed	4" "$("$USAGE" --rows | grep '	typed	')" "prints the number of words typed in a prompt"
drop_repo

new_repo
user_entry prompt_1 session_1 "$REPO" 2026-01-03T00:00:00Z '"build this\n\n<pasted_content id=\"a1\">\nthe header is blue\n</pasted_content id=\"a1\">\n<pasted_content id=\"b2\">\nthe footer is red\n</pasted_content id=\"b2\">"'
assert_equals "1767398400	session_1	pasted	2" "$("$USAGE" --rows | grep '	pasted	')" "prints the number of blocks pasted into a prompt"
drop_repo

new_repo
user_entry prompt_1 session_1 "$REPO" 2026-01-03T00:00:00Z '"build this\n\n<pasted_content id=\"a1\">\nthe header is blue\n</pasted_content id=\"a1\">"'
assert_equals "1767398400	session_1	pasted-words	4" "$("$USAGE" --rows | grep '	pasted-words	')" "prints the number of words pasted into a prompt"
drop_repo

new_repo
user_entry prompt_1 session_1 "$REPO" 2026-01-03T00:00:00Z '"build this\n\n<pasted_content id=\"a1\">\nthe header is blue\n</pasted_content id=\"a1\">"'
assert_equals "1767398400	session_1	typed	2" "$("$USAGE" --rows | grep '	typed	')" "leaves pasted words out of the words typed"
drop_repo

new_repo
result_entry answer_1 session_1 "$REPO" 2026-01-03T00:00:00Z '{"questions": [], "answers": {"Which one?": "A", "How long?": "10 minutes"}}' '[{"type": "tool_result", "content": "answered"}]'
assert_equals "1767398400	session_1	answered	2" "$("$USAGE" --rows | grep '	answered	')" "prints the number of questions answered"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
