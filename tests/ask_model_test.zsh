#!/usr/bin/env zsh
# Tests for bin/ask-model.sh, the one way every script asks a model a single
# question. Each case runs against a stubbed `claude`.
#
# Usage: zsh tests/ask_model_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ASK="$SCRIPT_DIR/../bin/ask-model.sh"

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

new_case() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/ask_model_test.XXXXXX")"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/claude" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/args"
cat > "$WORK/stdin"
printf '%s\n' "\${CLAUDE_REPLY:-Count: 0}"
exit "\${CLAUDE_EXIT:-0}"
SH
  chmod +x "$WORK/bin/claude"
  printf '{}\n' > "$WORK/models.json"
}

drop_case() {
  rm -rf "$WORK"
}

ask() {
  printf 'the question\n' | PATH="$WORK/bin:$PATH" SYMPHONY_AGENT_MODELS_FILE="$WORK/models.json" \
    "$ASK" counter sonnet 'Count: [0-9]+' 'You count things.'
}

model_asked() {
  awk 'want { print; exit } $0 == "--model" { want = 1 }' "$WORK/args" 2>/dev/null
}

echo "ask-model.sh:"

new_case
printf '{ "counter": "haiku" }\n' > "$WORK/models.json"
ask >/dev/null 2>&1
assert_equals "haiku" "$(model_asked)" "asks the model the agent models file names for the run"
drop_case

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
