#!/usr/bin/env zsh
# Tests for bin/stop-check.sh. Every case writes its transcript into a
# throwaway directory, so no real transcript is read.
#
# Usage: zsh tests/stop_check_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CHECK="$SCRIPT_DIR/../bin/stop-check.sh"

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

echo "the Stop hooks in hooks.json:"

assert_equals '${CLAUDE_PLUGIN_ROOT}/bin/stop-check.sh check' \
  "$(jq -r '.hooks.Stop[].hooks[].command | select(test("stop-check"))' "$SCRIPT_DIR/../hooks/hooks.json")" \
  "registers the plain-text question check on Stop"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
