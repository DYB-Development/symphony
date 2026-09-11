#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
RENDER="$SCRIPT_DIR/../bin/render-plan.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
  fi
}

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

echo "render-plan.sh:"

"$RENDER" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a repo and an issue number"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
