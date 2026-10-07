#!/usr/bin/env zsh
# Tests for bin/check-content.sh. Every case checks a throwaway list of rules
# against throwaway files, so no real instruction file is read.
#
# Usage: zsh tests/check_content_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CHECK="$SCRIPT_DIR/../bin/check-content.sh"

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

new_root() {
  ROOT="$(mktemp -d "${TMPDIR:-/tmp}/check_content_test.XXXXXX")"
  printf 'Mark each step as you start it.\nNever merge.\n' > "$ROOT/scribe.md"
}

drop_root() { rm -rf "$ROOT"; }

rules() { printf '%s\n' "$1" > "$ROOT/rules.json"; }

check() { "$CHECK" "$ROOT/rules.json" "$ROOT" >/dev/null 2>&1; echo $?; }

echo "check-content.sh:"

new_root
rules '{"version": 1, "rules": [{"file": "scribe.md", "contains": "Mark each step as you start it."}]}'
assert_equals "0" "$(check)" "passes when a rule's required text is in its file"
drop_root

new_root
rules '{"version": 1, "rules": [{"file": "scribe.md", "contains": "Open the pull request."}]}'
assert_equals "1" "$(check)" "fails when a rule's required text is missing from its file"
drop_root

new_root
rules '{"version": 1, "rules": [{"file": "scribe.md", "absent": "Never merge."}]}'
assert_equals "1" "$(check)" "fails when a rule's forbidden text is in its file"
drop_root

new_root
rules '{"version": 3, "rules": []}'
assert_equals "Checked against rules version 3" "$("$CHECK" "$ROOT/rules.json" "$ROOT" 2>&1 | head -1)" \
  "prints the version of the list of rules it checked"
drop_root

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
