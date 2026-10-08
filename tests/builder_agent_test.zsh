#!/usr/bin/env zsh
# Tests for agents/builder.md: the steps the progress bar counts, the model it
# runs on, and what its report ends with.
#
# Usage: zsh tests/builder_agent_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
BUILDER="$SCRIPT_DIR/../agents/builder.md"

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

echo "agents/builder.md:"

assert_equals "1. Read the work item and the code it touches
2. Build the acceptance criteria
3. Update the readme
4. Run the check
5. Report" "$(grep -E '^[0-9]+\. \*\*' "$BUILDER" 2>/dev/null | sed -E 's/^([0-9]+\.) \*\*([^*]+)\*\*.*/\1 \2/; s/\.$//')" \
  "numbers its steps in order: read, build, update the readme, check, report"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
