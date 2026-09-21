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
git -C "$REPO" symbolic-ref HEAD refs/heads/feature
entry msg_1 feature "$REPO" 10 20 30 40
entry msg_2 main "$REPO" 1 1 1 1
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "leaves out a message recorded on another branch"
drop_repo

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
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/${${REPO//\//-}}/session.jsonl"
mkdir -p "${TRANSCRIPT:h}"
entry msg_1 main "$REPO" 10 20 30 40
assert_equals "Input: 10
Output: 20
Cache read: 30
Cache write: 40
Total: 100" "$("$USAGE")" "reads the project directory named for the repo"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
