#!/usr/bin/env zsh
# Tests for bin/worktree-databases.sh. Every case runs against a throwaway main
# clone and linked worktree, with bun replaced by a stub that records each run.
#
# Usage: zsh tests/worktree_databases_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WORKTREE_DATABASES="$SCRIPT_DIR/../bin/worktree-databases.sh"

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

new_package_clones() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/worktree_databases_test.XXXXXX")"
  BASE="${BASE:A}"
  git init -q -b main "$BASE/app"
  echo "${1:-{\"scripts\": {\"worktree:db:create\": \"x\", \"worktree:db:drop\": \"x\"}}}" > "$BASE/app/package.json"
  git -C "$BASE/app" add package.json
  git -C "$BASE/app" commit -q -m init
  git -C "$BASE/app" worktree add -q -b feature "$BASE/app-feature"
  LINKED="$BASE/app-feature"
  RUNS="$BASE/runs"
  touch "$RUNS"
  mkdir -p "$BASE/stubs"
  cat > "$BASE/stubs/bun" <<BUN
#!/usr/bin/env bash
echo "\$(pwd -P) \$*" >> "$RUNS"
BUN
  chmod +x "$BASE/stubs/bun"
}

drop_clones() {
  cd "$SCRIPT_DIR"
  rm -rf "$BASE"
}

echo "worktree-databases.sh:"

new_package_clones
PATH="$BASE/stubs:$PATH" "$WORKTREE_DATABASES" create "$LINKED" >/dev/null 2>&1
assert_equals "$LINKED run worktree:db:create" "$(cat "$RUNS")" \
  "runs the app's create script with Bun from the worktree's root"
drop_clones

new_package_clones
PATH="$BASE/stubs:$PATH" "$WORKTREE_DATABASES" drop "$LINKED" >/dev/null 2>&1
assert_equals "$LINKED run worktree:db:drop" "$(cat "$RUNS")" \
  "runs the app's drop script with Bun from the worktree's root"
drop_clones

new_package_clones '{"scripts": {"worktree:db:create": "x"}}'
PATH="$BASE/stubs:$PATH" "$WORKTREE_DATABASES" create "$LINKED" >/dev/null 2>&1
assert_equals "0 " "$? $(cat "$RUNS")" "runs nothing for an app missing either script and exits successfully"
drop_clones

new_package_clones
NOT_A_CHECKOUT="$(mktemp -d "${TMPDIR:-/tmp}/not_a_checkout.XXXXXX")"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DATABASES" create "$NOT_A_CHECKOUT" >/dev/null 2>&1
assert_equals "64" "$?" "prints its usage and exits 64 for a path that is not a git checkout"
rm -rf "$NOT_A_CHECKOUT"
drop_clones

new_package_clones
PATH="$BASE/stubs:$PATH" "$WORKTREE_DATABASES" destroy "$LINKED" >/dev/null 2>&1
assert_equals "64 " "$? $(cat "$RUNS")" "prints its usage, exits 64 and runs nothing for an action it does not know"
drop_clones

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
