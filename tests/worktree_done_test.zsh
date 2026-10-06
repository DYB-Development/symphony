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

new_rails_clones() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/worktree_done_test.XXXXXX")"
  BASE="${BASE:A}"
  git init -q --bare -b main "$BASE/origin.git"
  git clone -q "$BASE/origin.git" "$BASE/app" 2>/dev/null
  mkdir -p "$BASE/app/config" "$BASE/app/bin" "$BASE/stubs"
  echo "${1:-<% worktree = \"\" %>}" > "$BASE/app/config/database.yml"
  cat > "$BASE/app/bin/rails" <<'RAILS'
#!/usr/bin/env bash
echo "shop_${RAILS_ENV}_app_feature"
RAILS
  chmod +x "$BASE/app/bin/rails"
  git -C "$BASE/app" add config bin
  git -C "$BASE/app" commit -q -m init
  git -C "$BASE/app" push -q origin main
  git -C "$BASE/app" worktree add -q -b feature "$BASE/app-feature"
  MAIN="$BASE/app"
  LINKED="$BASE/app-feature"
  DATABASES="$BASE/databases"
  DROPPED="$BASE/dropped"
  printf '%s\n' shop_development shop_test shop_development_app_feature shop_test_app_feature > "$DATABASES"
  touch "$DROPPED"
  cat > "$BASE/stubs/psql" <<PSQL
#!/usr/bin/env bash
cat "$DATABASES"
PSQL
  cat > "$BASE/stubs/dropdb" <<DROPDB
#!/usr/bin/env bash
echo "\${@: -1}" >> "$DROPPED"
DROPDB
  chmod +x "$BASE/stubs/psql" "$BASE/stubs/dropdb"
}

new_package_clones() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/worktree_done_test.XXXXXX")"
  BASE="${BASE:A}"
  git init -q --bare -b main "$BASE/origin.git"
  git clone -q "$BASE/origin.git" "$BASE/app" 2>/dev/null
  echo '{"scripts": {"worktree:db:create": "x", "worktree:db:drop": "x"}}' > "$BASE/app/package.json"
  git -C "$BASE/app" add package.json
  git -C "$BASE/app" commit -q -m init
  git -C "$BASE/app" push -q origin main
  git -C "$BASE/app" worktree add -q -b feature "$BASE/app-feature"
  MAIN="$BASE/app"
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

new_clones
git -C "$LINKED" commit -q --allow-empty -m "Work not merged"
"$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "there" "$([[ -d $LINKED ]] && echo there || echo gone)" "keeps a worktree whose commits are not on the remote's main branch"
drop_clones

new_rails_clones
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "shop_development_app_feature shop_test_app_feature" "$(sort "$DROPPED" | tr '\n' ' ' | sed 's/ $//')" \
  "drops the development and test databases the worktree's app names"
drop_clones

new_rails_clones
printf '%s\n' shop_test_app_feature_0 shop_test_app_feature_1 >> "$DATABASES"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "shop_test_app_feature_0 shop_test_app_feature_1" "$(grep '_[0-9]$' "$DROPPED" | sort | tr '\n' ' ' | sed 's/ $//')" \
  "drops the numbered copies of the test database made for parallel tests"
drop_clones

new_rails_clones '<% require "digest"; worktree = "" %>'
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "shop_development_app_feature shop_test_app_feature" "$(sort "$DROPPED" | tr '\n' ' ' | sed 's/ $//')" \
  "drops the databases of an app whose config keeps long names short"
drop_clones

new_rails_clones
touch "$LINKED/unsaved.txt"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "" "$(cat "$DROPPED")" "keeps the databases of a worktree with changes not committed"
drop_clones

new_rails_clones
printf '%s\n' shop_test_app_feature_two >> "$DATABASES"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "" "$(grep -xE 'shop_development|shop_test|shop_test_app_feature_two' "$DROPPED")" \
  "leaves the main clone's databases and any whose name only starts the same"
drop_clones

new_rails_clones
printf '%s\n' shop_development shop_test shop_test_app_feature > "$DATABASES"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "gone" "$([[ -d $LINKED ]] && echo there || echo gone)" "removes a worktree whose development database was never created"
drop_clones

new_package_clones
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "$LINKED run worktree:db:drop" "$(cat "$RUNS")" \
  "runs a package app's drop script from the worktree before removing it"
drop_clones

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
