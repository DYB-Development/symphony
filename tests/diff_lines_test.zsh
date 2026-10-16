#!/usr/bin/env zsh
# Tests for bin/diff-lines.sh, the one reader of a diff that the touched-line
# check, the pattern scan and the test inventory share.
#
# Usage: zsh tests/diff_lines_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
READER="$SCRIPT_DIR/../bin/diff-lines.sh"

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

echo "diff-lines.sh:"

assert_equals $'RIGHT\tapp/my quote.rb\t2\t  def convert; end' \
  "$(printf 'diff --git a/app/my quote.rb b/app/my quote.rb\n--- a/app/my quote.rb\t\n+++ b/app/my quote.rb\t\n@@ -1,2 +1,3 @@\n class Quote\n+  def convert; end\n end\n' | "$READER")" \
  "reads a path that holds a space and ends in a tab"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
