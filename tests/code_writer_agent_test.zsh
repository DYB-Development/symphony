#!/usr/bin/env zsh
# Tests for agents/code-writer.md: who it is, what it may touch, and what its
# report ends with.
#
# Usage: zsh tests/code_writer_agent_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WRITER="$SCRIPT_DIR/../agents/code-writer.md"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals "name: code-writer" "$(sed -n '2,/^---$/p' "$WRITER" 2>/dev/null | grep '^name:')" \
  "is the agent named code-writer, so a pipeline's agent step can name it"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
