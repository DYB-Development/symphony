#!/usr/bin/env zsh
# Tests for bin/main-clone-gate.sh. Every case runs against a throwaway main
# clone and a linked worktree of it, so no real repo is touched.
#
# Usage: zsh tests/main_clone_gate_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/main-clone-gate.sh"

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

new_clones() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/main_clone_gate_test.XXXXXX")"
  BASE="${BASE:A}"
  MAIN="$BASE/app"
  LINKED="$BASE/app-feature"
  git init -q "$MAIN"
  git -C "$MAIN" commit -q --allow-empty -m init
  git -C "$MAIN" worktree add -q -b feature "$LINKED"
}

drop_clones() {
  rm -rf "$BASE"
}

edit_payload() {
  jq -nc --arg tool "$1" --arg path "$2" --arg cwd "$3" \
    '{session_id: "s", tool_name: $tool, tool_input: {file_path: $path}, cwd: $cwd}'
}

bash_payload() {
  jq -nc --arg command "$1" --arg cwd "$2" \
    '{session_id: "s", tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}'
}

decision() {
  local reply
  reply=$(printf '%s' "$1" | "$GATE" check)
  [[ -n "$reply" ]] || { printf 'allow'; return; }
  printf '%s' "$reply" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}

echo "main-clone-gate.sh check:"

new_clones
assert_equals "deny" "$(decision "$(edit_payload Write "$MAIN/notes.md" "$MAIN")")" \
  "a write to a file in the main clone is refused"
drop_clones

new_clones
assert_equals "allow" "$(decision "$(edit_payload Write "$LINKED/notes.md" "$LINKED")")" \
  "a write to a file in a linked worktree is let through"
drop_clones

new_clones
notebook=$(jq -nc --arg path "$MAIN/book.ipynb" --arg cwd "$MAIN" \
  '{session_id: "s", tool_name: "NotebookEdit", tool_input: {notebook_path: $path}, cwd: $cwd}')
assert_equals "deny" "$(decision "$notebook")" \
  "a notebook edit in the main clone is refused"
drop_clones

new_clones
assert_equals "deny" "$(decision "$(bash_payload 'git commit -m wip' "$MAIN")")" \
  "a git commit run in the main clone is refused"
drop_clones

new_clones
let_through=()
for sub in checkout switch merge rebase reset stash pull; do
  [[ "$(decision "$(bash_payload "git $sub" "$MAIN")")" == deny ]] || let_through+=("$sub")
done
assert_equals "" "${let_through[*]}" \
  "every other git command that changes files or the branch is refused in the main clone"
drop_clones

new_clones
assert_equals "allow" "$(decision "$(bash_payload "git -C $LINKED commit -m wip" "$MAIN")")" \
  "a git commit pointed at a linked worktree is let through from the main clone"
drop_clones

new_clones
assert_equals "deny" "$(decision "$(bash_payload "cd $MAIN && git pull" "$LINKED")")" \
  "a git pull after a cd into the main clone is refused"
drop_clones

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
