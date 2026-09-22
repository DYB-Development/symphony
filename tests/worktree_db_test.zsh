#!/usr/bin/env zsh
# Tests for claude/bin/worktree-db.sh. Every case runs against a throwaway app
# directory so no real config/database.yml is ever rewritten.
#
# Usage: zsh tests/worktree_db_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WORKTREE_DB="$SCRIPT_DIR/../bin/worktree-db.sh"

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

new_app() {
  APP="$(mktemp -d "${TMPDIR:-/tmp}/worktree_db_test.XXXXXX")"
  mkdir -p "$APP/config"
  cat > "$APP/config/database.yml" <<'YAML'
default: &default
  adapter: postgresql

development:
  primary:
    <<: *default
    database: shop_development
  cache:
    <<: *default
    database: shop_development_cache

test:
  <<: *default
  database: shop_test

production:
  primary:
    <<: *default
    database: shop_production
YAML
}

drop_app() {
  cd "$SCRIPT_DIR"
  rm -rf "$APP"
}

database_line() {
  grep -F "database: $1" "$APP/config/database.yml"
}

echo "worktree-db.sh:"

new_app
"$WORKTREE_DB" "$APP" >/dev/null
assert_equals "    database: shop_development<%= worktree %>" "$(database_line shop_development\<)" \
  "adds the worktree suffix to a development database name"
drop_app

new_app
"$WORKTREE_DB" "$APP" >/dev/null
assert_equals "  database: shop_test<%= worktree %>" "$(database_line shop_test)" \
  "adds the worktree suffix to the test database name"
drop_app

new_app
"$WORKTREE_DB" "$APP" >/dev/null
assert_equals '<% worktree = File.file?(Rails.root.join(".git")) ? "_#{Rails.root.basename.to_s.gsub(/\W/, "_")}" : "" %>' \
  "$(head -1 "$APP/config/database.yml")" \
  "defines the suffix from the worktree folder on the first line"
drop_app

new_app
"$WORKTREE_DB" "$APP" >/dev/null
once="$(cat "$APP/config/database.yml")"
"$WORKTREE_DB" "$APP" >/dev/null
assert_equals "$once" "$(cat "$APP/config/database.yml")" \
  "changes nothing when the config was already converted"
drop_app

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
