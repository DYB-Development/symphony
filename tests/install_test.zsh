#!/usr/bin/env zsh
# Tests for install.sh. Every case runs against a throwaway config directory so
# the machine's own Claude configuration is never touched.
#
# Usage: zsh tests/install_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
INSTALL="$ROOT/install.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  [[ "$1" == "$2" ]] && ok "$3" || { fail "$3"; printf '      want: %s\n      got:  %s\n' "$1" "$2"; }
}

fresh_config() {
  local d
  d="$(mktemp -d)"
  printf '%s' "$d"
}

echo "install.sh:"

CONFIG="$(fresh_config)"
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1

assert_equals "$ROOT/rules" "$(readlink "$CONFIG/rules")" \
  "links the rules directory at the package"

rm -rf "$CONFIG"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
