#!/usr/bin/env zsh
# Tests for bin/question-check.sh.
#
# Usage: zsh tests/question_check_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CHECK="$SCRIPT_DIR/../bin/question-check.sh"

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

STUBS="$(mktemp -d "${TMPDIR:-/tmp}/question_check_test.XXXXXX")"
trap 'rm -rf "$STUBS"' EXIT
cat > "$STUBS/claude" <<'SH'
#!/usr/bin/env bash
cat > "$(dirname "$0")/stdin"
printf '%s\n' "${READER_REPLY:-Flagged: 0}"
exit "${READER_EXIT:-0}"
SH
chmod +x "$STUBS/claude"

FLAGGED_REPLY='1. "Should the shop run the reconciler?"
   Means: It asks whether something called the reconciler should run.
   Flag: The reconciler is never explained.

Flagged: 1'

QUESTION='{session_id: "s1", tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Should the shop run the reconciler?", options: [{label: "Run it", description: "The reconciler runs tonight."}, {label: "Skip it", description: "Nothing runs."}]}]}}'

check() {
  jq -nc "$QUESTION" |
    SYMPHONY_OVERLAY_DIR="$STUBS/no-overlay" SYMPHONY_AGENT_MODELS_FILE="$STUBS/no-models.json" \
    PATH="$STUBS:$PATH" "$CHECK" check
}

echo "question-check.sh check:"

assert_equals "deny" "$(READER_REPLY="$FLAGGED_REPLY" READER_EXIT=0 check | jq -r '.hookSpecificOutput.permissionDecision')" \
  "refuses a question the reader flags"

assert_equals 'The owner could not follow this question on one read. Rewrite it in plain words and ask again.

1. "Should the shop run the reconciler?"
   Means: It asks whether something called the reconciler should run.
   Flag: The reconciler is never explained.' \
  "$(READER_REPLY="$FLAGGED_REPLY" READER_EXIT=0 check | jq -r '.hookSpecificOutput.permissionDecisionReason')" \
  "lists each flagged sentence with the reader's note and asks for a rewrite"

assert_equals "" "$(READER_REPLY="Flagged: 0" READER_EXIT=0 check)" \
  "lets a question the reader followed through"

assert_equals "" "$(READER_REPLY="$FLAGGED_REPLY" READER_EXIT=1 check 2>/dev/null)" \
  "lets a question through when the reader fails"

assert_equals "question-check.sh: the draft reader failed, so the question was asked unchecked" \
  "$(READER_REPLY="$FLAGGED_REPLY" READER_EXIT=1 check 2>&1 >/dev/null)" \
  "warns in one line when the reader fails"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
