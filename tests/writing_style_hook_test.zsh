#!/usr/bin/env zsh
# Tests for claude/bin/writing-style-hook.sh, the hook that feeds the writing
# style rules into a session and into every subagent.
#
# Usage: zsh zsh/writing_style_hook_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
HOOK="$SCRIPT_DIR/../bin/writing-style-hook.sh"

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

run_hook() { jq -nc --arg e "$1" '{hook_event_name: $e}' | "$HOOK"; }

silence_rules() { export CLAUDE_WRITING_STYLE_FILE="$SCRIPT_DIR/does-not-exist.md"; }
restore_rules() { unset CLAUDE_WRITING_STYLE_FILE; }

echo "writing-style-hook.sh:"

assert_equals \
  "SubagentStart" \
  "$(run_hook SubagentStart | jq -r '.hookSpecificOutput.hookEventName')" \
  "echoes the incoming hook event name"

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
  fi
}

assert_contains \
  "No metaphors" \
  "$(run_hook SubagentStart | jq -r '.hookSpecificOutput.additionalContext')" \
  "carries the writing style rules as additional context"

PHRASES_FILE="$(mktemp "${TMPDIR:-/tmp}/banned_phrases.XXXXXX")"
printf 'synergise the deliverable\n' > "$PHRASES_FILE"
export CLAUDE_BANNED_PHRASES_FILE="$PHRASES_FILE"
assert_contains \
  "synergise the deliverable" \
  "$(run_hook SubagentStart | jq -r '.hookSpecificOutput.additionalContext')" \
  "carries the banned phrases list alongside the rules"
unset CLAUDE_BANNED_PHRASES_FILE
rm -f "$PHRASES_FILE"


RULES_DIR="${SCRIPT_DIR:h}/rules"
assert_contains \
  "$RULES_DIR" \
  "$(run_hook SubagentStart | jq -r '.hookSpecificOutput.additionalContext')" \
  "names the directory its rules were read from, as an absolute path"


VOICE_FILE="$(mktemp "${TMPDIR:-/tmp}/own_voice.XXXXXX")"
printf 'My own voice.\n' > "$VOICE_FILE"
assert_contains \
  "$RULES_DIR" \
  "$(CLAUDE_WRITING_STYLE_FILE="$VOICE_FILE" run_hook SubagentStart | jq -r '.hookSpecificOutput.additionalContext')" \
  "still names its own rules directory when the voice file is somewhere else"
rm -f "$VOICE_FILE"

silence_rules
assert_equals \
  "" \
  "$(run_hook SubagentStart 2>&1)" \
  "stays silent when the rules file is missing"
restore_rules

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
