#!/usr/bin/env zsh
# End-to-end test for claude/bin/worktree-db.sh: converts the config in a real
# git repo, adds a linked worktree, and renders the config the way Rails does
# from each checkout.
#
# Usage: zsh tests/worktree_db_smoke_test.zsh
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

development_database() {
  ruby -rerb -ryaml -rpathname -e '
    module Rails
      def self.root = Pathname(ARGV[0])
    end
    config = YAML.safe_load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true)
    puts config.dig("development", "primary", "database")
  ' "$1"
}

echo "worktree-db.sh (smoke):"

HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/worktree_db_smoke.XXXXXX")"
MAIN="$HOME_DIR/shop"
mkdir -p "$MAIN/config"
cat > "$MAIN/config/database.yml" <<'YAML'
development:
  primary:
    database: shop_development
YAML
git -C "$MAIN" init -q
"$WORKTREE_DB" "$MAIN" >/dev/null
git -C "$MAIN" add config/database.yml
git -C "$MAIN" -c user.name=test -c user.email=test@example.com commit -q -m config
git -C "$MAIN" worktree add -q "$HOME_DIR/shop-console"

assert_equals "shop_development" "$(development_database "$MAIN")" \
  "the main clone keeps its database name"
assert_equals "shop_development_shop_console" "$(development_database "$HOME_DIR/shop-console")" \
  "a linked worktree gets a database named after its folder"

rm -rf "$HOME_DIR"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
