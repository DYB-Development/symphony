#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CHECK="$SCRIPT_DIR/../bin/keep-working.sh"
GATE="$SCRIPT_DIR/../bin/owner-question.sh"

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

ROOT="${$(mktemp -d "${TMPDIR:-/tmp}/keep_working_test.XXXXXX"):A}"
trap 'rm -rf "$ROOT"' EXIT
export OWNER_QUESTION_DIR="$ROOT/marks"
export CLAUDE_CONFIG_DIR="$ROOT/config"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkdir -p "$ROOT/stubs" "$CLAUDE_CONFIG_DIR"
cat > "$ROOT/stubs/gh" <<'SH'
#!/usr/bin/env bash
[ -z "${GH_FAILS:-}" ] || exit 1
case "$1 $2" in
  "pr list") cat "$GH_DATA/prs.json" ;;
  "issue view") cat "$GH_DATA/issue-$3.json" ;;
  "issue list") cat "$GH_DATA/open.json" ;;
esac
SH
chmod +x "$ROOT/stubs/gh"
export PATH="$ROOT/stubs:$PATH"
export GH_DATA="$ROOT/gh"

new_repo() {
  rm -rf "$ROOT/origin.git" "$ROOT/shop" "$ROOT/shop-feature" "$OWNER_QUESTION_DIR" "$GH_DATA" "$CLAUDE_CONFIG_DIR/session-worktrees.tsv"
  mkdir -p "$GH_DATA"
  echo '[]' > "$GH_DATA/prs.json"
  git init -q --bare -b main "$ROOT/origin.git"
  git init -q -b main "$ROOT/shop"
  git -C "$ROOT/shop" remote add origin "$ROOT/origin.git"
  git -C "$ROOT/shop" commit -q --allow-empty -m base
  git -C "$ROOT/shop" push -q -u origin main
  git -C "$ROOT/shop" worktree add -q -b feature "$ROOT/shop-feature"
  printf '%s\t%s\n' "$ROOT/shop" "$ROOT/session.jsonl" "$ROOT/shop-feature" "$ROOT/session.jsonl" > "$CLAUDE_CONFIG_DIR/session-worktrees.tsv"
}

stop_input() {
  jq -nc --arg path "$ROOT/session.jsonl" --argjson tasks "${1:-[]}" \
    '{hook_event_name: "Stop", session_id: "s1", cwd: "/", transcript_path: $path, background_tasks: $tasks}'
}

stopping() {
  stop_input "${1:-[]}" | "$CHECK" check 2>/dev/null
}

reason() {
  stopping "$@" | jq -r '.reason // empty'
}

commit_work() {
  git -C "$ROOT/shop-feature" commit -q --allow-empty -m work
}

push_work() {
  git -C "$ROOT/shop-feature" push -q -u origin feature 2>/dev/null
}

echo "keep-working.sh check:"

new_repo
touch "$ROOT/shop-feature/new.txt"
assert_contains "uncommitted changes" "$(reason)" "refuses a stop while the session's worktree has uncommitted changes"

new_repo
assert_equals "" "$(stopping)" "lets a session stop in a worktree where nothing has been started"

new_repo
commit_work
assert_contains "unpushed commits" "$(reason)" "refuses a stop while the branch has unpushed commits"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
