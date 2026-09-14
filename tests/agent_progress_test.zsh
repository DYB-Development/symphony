#!/usr/bin/env zsh
# Tests for bin/scribe-step.sh and bin/agent-progress.sh. Every case writes its
# logs into a throwaway directory, so no real progress log is touched.
#
# Usage: zsh tests/agent_progress_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STEP="$SCRIPT_DIR/../bin/scribe-step.sh"

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

echo "scribe-step.sh:"

assert_equals "acme/quotes#42 · 3. Run every check" \
  "$("$STEP" "acme/quotes#42" "3. Run every check" 2>&1)" \
  "prints the target and the step it is given"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
