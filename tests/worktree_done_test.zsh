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

STUBS="$(mktemp -d "${TMPDIR:-/tmp}/worktree_done_stubs.XXXXXX")"
STUBS="${STUBS:A}"
cat > "$STUBS/stub" <<'STUB'
#!/usr/bin/env bash
case "${0##*/}" in
  rails) echo "shop_${RAILS_ENV}_app_feature" ;;
  psql) cat "$WORKTREE_DONE_TEST_BASE/databases" ;;
  dropdb) echo "${@: -1}" >> "$WORKTREE_DONE_TEST_BASE/dropped" ;;
  bun)
    [ ! -f "$WORKTREE_DONE_TEST_BASE/bun_fails" ] || exit 1
    echo "$(pwd -P) $*" >> "$WORKTREE_DONE_TEST_BASE/runs" ;;
esac
STUB
chmod +x "$STUBS/stub"
WORKTREE_DONE_TEST_BASE=/nonexistent "$STUBS/stub" >/dev/null 2>&1
mkdir -p "$STUBS/path"
for name in rails psql dropdb bun; do ln -s "$STUBS/stub" "$STUBS/path/$name"; done

template() {
  local dir="$STUBS/$1"
  git init -q --bare --template= -b main "$dir/origin.git"
  git clone -q --template= "$dir/origin.git" "$dir/app" 2>/dev/null
  case "$1" in
    rails)
      mkdir -p "$dir/app/config" "$dir/app/bin"
      ln -s "$STUBS/path/rails" "$dir/app/bin/rails"
      git -C "$dir/app" add bin ;;
    package)
      echo '{"scripts": {"worktree:db:create": "x", "worktree:db:drop": "x"}}' > "$dir/app/package.json"
      git -C "$dir/app" add package.json ;;
  esac
  git -C "$dir/app" commit -q --allow-empty -m init
  git -C "$dir/app" push -q origin main
}
template plain
template rails
template package

copy_template() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/worktree_done_test.XXXXXX")"
  BASE="${BASE:A}"
  export WORKTREE_DONE_TEST_BASE="$BASE"
  cp -R "$STUBS/$1/origin.git" "$STUBS/$1/app" "$BASE/"
  git -C "$BASE/app" remote set-url origin "$BASE/origin.git"
  MAIN="$BASE/app"
  LINKED="$BASE/app-feature"
}

add_linked() {
  git -C "$MAIN" worktree add -q -b feature "$LINKED"
}

new_clones() {
  copy_template plain
  add_linked
}

new_rails_clones() {
  copy_template rails
  mkdir -p "$BASE/app/config" "$BASE/stubs"
  echo "${1:-<% worktree = \"\" %>}" > "$BASE/app/config/database.yml"
  git -C "$BASE/app" add config
  git -C "$BASE/app" commit -q -m config
  git -C "$BASE/app" push -q origin main
  add_linked
  DATABASES="$BASE/databases"
  DROPPED="$BASE/dropped"
  printf '%s\n' shop_development shop_test shop_development_app_feature shop_test_app_feature > "$DATABASES"
  touch "$DROPPED"
  ln -s "$STUBS/path/psql" "$BASE/stubs/psql"
  ln -s "$STUBS/path/dropdb" "$BASE/stubs/dropdb"
}

new_package_clones() {
  copy_template package
  add_linked
  RUNS="$BASE/runs"
  touch "$RUNS"
  mkdir -p "$BASE/stubs"
  ln -s "$STUBS/path/bun" "$BASE/stubs/bun"
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

new_package_clones
touch "$LINKED/unsaved.txt"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "" "$(cat "$RUNS")" "runs no drop script for a worktree the cleanup refuses"
drop_clones

new_package_clones
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" --kind rails "$LINKED" >/dev/null 2>&1
assert_equals "64 there" "$? $([[ -d $LINKED ]] && echo there || echo gone)" \
  "refuses an option naming one kind, since cleanup always drops every kind"
drop_clones

new_package_clones
touch "$BASE/bun_fails"
OUTPUT="$(PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" 2>&1)"
assert_equals "1 there feature the package app" \
  "$? $([[ -d $LINKED ]] && echo there || echo gone) $(git -C "$MAIN" branch --list feature --format='%(refname:short)') $(grep -o 'the package app' <<<"$OUTPUT" | head -1)" \
  "keeps the worktree and its branch and names the kind when a drop fails"
drop_clones

new_package_clones
touch "$BASE/bun_fails"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
rm "$BASE/bun_fails"
PATH="$BASE/stubs:$PATH" "$WORKTREE_DONE" "$LINKED" >/dev/null 2>&1
assert_equals "$LINKED run worktree:db:drop gone" "$(cat "$RUNS") $([[ -d $LINKED ]] && echo there || echo gone)" \
  "drops the databases and removes the worktree when cleanup runs again after a failed drop is fixed"
drop_clones

rm -rf "$STUBS"
echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
