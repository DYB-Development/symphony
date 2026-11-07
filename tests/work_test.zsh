#!/usr/bin/env zsh
# Tests for bin/work.sh. Every case runs inside a throwaway git repo so no real
# .work is ever created or appended to.
#
# Usage: zsh tests/work_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WORK_SH="$SCRIPT_DIR/../bin/work.sh"

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

new_repo() {
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/work_test.XXXXXX")"
  git -C "$REPO" init -q
  cd "$REPO"
}

drop_repo() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
}

echo "work.sh:"

new_repo
"$WORK_SH" "https://github.com/acme/shop/issues/28" "shop#28" >/dev/null
assert_equals '{"address":"https://github.com/acme/shop/issues/28","label":"shop#28"}' "$(cat .work 2>&1)" \
  "records the address and label it is given as one JSON object"
drop_repo

new_repo
"$WORK_SH" "https://github.com/acme/shop/issues/28" "shop#28" >/dev/null
"$WORK_SH" "https://acme.atlassian.net/browse/ACME-1234" "ACME-1234" >/dev/null
assert_equals '{"address":"https://github.com/acme/shop/issues/28","label":"shop#28"}
{"address":"https://acme.atlassian.net/browse/ACME-1234","label":"ACME-1234"}' "$(cat .work 2>&1)" \
  "appends a second piece of work on its own line below the first"
drop_repo

new_repo
"$WORK_SH" "https://github.com/acme/shop/issues/28" "shop#28" >/dev/null
"$WORK_SH" "https://github.com/acme/shop/issues/28" "Export quotes" >/dev/null
assert_equals '{"address":"https://github.com/acme/shop/issues/28","label":"shop#28"}' "$(cat .work 2>&1)" \
  "records an address it already holds once, even under another label"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
