#!/usr/bin/env zsh
# Tests for commands/run-work.md: which agents it hands a pipeline's agent
# steps to, and what it hands them.
#
# Usage: zsh tests/run_work_command_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
COMMAND="$SCRIPT_DIR/../commands/run-work.md"

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

handoff() { awk -v agent="**\`$1\`**" 'index($0, "- " agent) { on = 1; print; next } on && /^   - \*\*/ { exit } on && /^   Then go back/ { exit } on { print }' "$COMMAND"; }

echo "commands/run-work.md:"

assert_equals "worktree title request criterion report" \
  "$(handoff test-writer | tr '\n' ' ' | grep -oE 'worktree|title|request|acceptance criterion|pipeline.sh report <id>' | sed 's/acceptance criterion/criterion/; s/pipeline.sh report <id>/report/' | tr '\n' ' ' | sed 's/ $//')" \
  "hands a test writer step to test-writer with the worktree, title, request and acceptance criterion, then posts its report"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
