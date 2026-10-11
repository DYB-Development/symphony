#!/usr/bin/env zsh
# Tests for agents/test-writer.md: who it is, what it may touch, and what its
# report ends with.
#
# Usage: zsh tests/test_writer_agent_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WRITER="$SCRIPT_DIR/../agents/test-writer.md"

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

echo "agents/test-writer.md:"

assert_equals "name: test-writer" "$(sed -n '2,/^---$/p' "$WRITER" 2>/dev/null | grep '^name:')" \
  "is the agent named test-writer, so a pipeline's agent step can name it"

assert_equals "" "$(sed -n '2,/^---$/p' "$WRITER" | grep '^model:')" \
  "names no model, so it runs on whatever model the pipeline step names"

assert_equals "1" "$(sed -n '/^## What you never do/,/^## /p' "$WRITER" | grep -c 'Never commit')" \
  "forbids committing, since a later step of the pipeline commits"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
