#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
JUDGE="$SCRIPT_DIR/../bin/judge-claims.sh"
RULES="$SCRIPT_DIR/../rules/claim-checking.md"

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

section_named() {
  awk -v want="$1" '$0 == want { found = 1 } END { print found ? "yes" : "no" }' "$RULES"
}

echo "the claim rules, on judging:"

assert_equals "yes" "$(section_named '## What the judge is given')" \
  "say what the judge sees and what it never sees"

assert_equals "yes" "$(section_named '## What the judge returns')" \
  "say the shape a verdict comes back in"

echo ""
echo "judge-claims.sh:"

"$JUDGE" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a claims file to judge"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
