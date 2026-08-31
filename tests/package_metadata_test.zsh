#!/usr/bin/env zsh
# Tests that the package says who owns it, what it is licensed under, and where
# it lives. A plugin shared with anyone is read from its manifests before it is
# read from its code, so a stale owner or a missing licence is a defect.
#
# Usage: zsh tests/package_metadata_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  [[ "$1" == "$2" ]] && ok "$3" || { fail "$3"; printf '      want: %s\n      got:  %s\n' "$1" "$2"; }
}

OWNER="DYB-Development"
REPO="https://github.com/$OWNER/symphony"

echo "package metadata:"

assert_equals "MIT" \
  "$(sed -n '1s/.*\(MIT\) License.*/\1/p' "$ROOT/LICENSE" 2>/dev/null)" \
  "carries an MIT licence"

assert_equals "MIT" \
  "$(jq -r '.license // ""' "$ROOT/.claude-plugin/plugin.json")" \
  "names that licence in the plugin manifest"

assert_equals "$REPO" \
  "$(jq -r '.homepage // ""' "$ROOT/.claude-plugin/plugin.json")" \
  "points at the repository it actually lives in"

assert_equals "$OWNER" \
  "$(jq -r '.author.name // ""' "$ROOT/.claude-plugin/plugin.json")" \
  "names the organisation that owns it, not a person"

assert_equals "$OWNER" \
  "$(jq -r '.owner.name // ""' "$ROOT/.claude-plugin/marketplace.json")" \
  "names that same owner in the marketplace"

assert_equals "" \
  "$(grep -rl 'tylercschneider' $(git -C "$ROOT" ls-files) 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" \
  "names no personal account anywhere it ships"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
