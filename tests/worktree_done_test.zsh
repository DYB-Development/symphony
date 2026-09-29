#!/usr/bin/env zsh
# Tests for bin/worktree-done.sh. Every case runs against a throwaway origin, a
# main clone of it and a linked worktree, so no real repo or database is touched.
#
# Usage: zsh tests/worktree_done_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WORKTREE_DONE="$SCRIPT_DIR/../bin/worktree-done.sh"

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
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/worktree_done_test.XXXXXX")"
  BASE="${BASE:A}"
  git init -q --bare -b main "$BASE/origin.git"
  git clone -q "$BASE/origin.git" "$BASE/app" 2>/dev/null
  git -C "$BASE/app" commit -q --allow-empty -m init
  git -C "$BASE/app" push -q origin main
  git -C "$BASE/app" worktree add -q -b feature "$BASE/app-feature"
  MAIN="$BASE/app"
  LINKED="$BASE/app-feature"
}

drop_clones() {
  cd "$SCRIPT_DIR"
  rm -rf "$BASE"
}

echo "worktree-done.sh:"

new_clones
"$WORKTREE_DONE" "$MAIN" >/dev/null 2>&1
assert_equals "65" "$?" "refuses the main clone"
drop_clones

new_clones
"$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "gone" "$([[ -d $LINKED ]] && echo there || echo gone)" "removes a worktree whose branch is merged"
drop_clones

new_clones
"$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "" "$(git -C "$MAIN" branch --list feature)" "deletes the branch the worktree held"
drop_clones

new_clones
touch "$LINKED/unsaved.txt"
"$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "there" "$([[ -d $LINKED ]] && echo there || echo gone)" "keeps a worktree with changes not committed"
drop_clones

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
