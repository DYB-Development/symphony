#!/usr/bin/env zsh
# Tests for bin/conformance.sh. Each case runs against a stubbed `gh` that
# answers from files written for the case, and a stubbed `claude`.
#
# Usage: zsh tests/conformance_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CONFORMANCE="$SCRIPT_DIR/../bin/conformance.sh"

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
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/conformance_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/repo"
  : > "$WORK/ticket"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr view") cat "$WORK/ticket" ;;
  "issue view") cat "$WORK/issue" ;;
esac
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/bin/claude" <<SH
#!/usr/bin/env bash
cat >> "$WORK/asked"
printf '%s\n' "\${CLAUDE_REPLY:-1: none}"
SH
  chmod +x "$WORK/bin/claude"
  DRAFT_FILE="$WORK/repo/.review-7.json"
  printf '{ "tests": [], "hits": [] }\n' > "$WORK/repo/.review-7.tests.json"
  RESULT="$WORK/repo/.review-7.conformance.json"
}

drop_case() {
  rm -rf "$WORK"
}

conformance() {
  PATH="$WORK/bin:$PATH" SYMPHONY_AGENT_MODELS_FILE="$WORK/no-models.json" "$CONFORMANCE" acme/quotes 7 "$DRAFT_FILE"
}

render() {
  "$CONFORMANCE" --render "$RESULT"
}

echo "conformance.sh:"

new_case
conformance >/dev/null 2>&1
assert_equals "No ticket referenced." "$(render 2>&1)" \
  "reports that no ticket was referenced when the pull request names none"
drop_case

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
