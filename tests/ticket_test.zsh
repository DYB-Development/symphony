#!/usr/bin/env zsh
# Tests for claude/bin/ticket.sh. Every case runs inside a throwaway git repo so
# no real .ticket is ever created or appended to.
#
# Usage: zsh zsh/ticket_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
TICKET="$SCRIPT_DIR/../bin/ticket.sh"

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
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/ticket_test.XXXXXX")"
  git -C "$REPO" init -q
  cd "$REPO"
}

drop_repo() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
}

echo "ticket.sh:"

new_repo
"$TICKET" "ACME-1234" >/dev/null
assert_equals "ACME-1234" "$(cat .ticket)" "records the ticket it is given"
drop_repo

new_repo
"$TICKET" "ACME-1234" >/dev/null
"$TICKET" "ACME-1240" >/dev/null
assert_equals "ACME-1234
ACME-1240" "$(cat .ticket)" "appends a second ticket below the first"
drop_repo

new_repo
"$TICKET" "ACME-1234" >/dev/null
"$TICKET" "ACME-1234" >/dev/null
assert_equals "ACME-1234" "$(cat .ticket)" "records a repeated reference once"
drop_repo

new_repo
"$TICKET" "ACME-1234" >/dev/null
"$TICKET" "ACME-1240" >/dev/null
assert_equals "## Ticket Billed Against

- ACME-1234
- ACME-1240" "$("$TICKET" --render)" "renders the section as a bullet per reference"
drop_repo

new_repo
assert_equals "## Ticket Billed Against

Not specified." "$("$TICKET" --render)" "renders Not specified when nothing was recorded"
drop_repo

new_repo
"$TICKET" >/dev/null 2>&1
assert_equals "64" "$?" "exits with a usage code when given no reference"
drop_repo

new_repo
"$TICKET" "   " >/dev/null 2>&1
assert_equals "64" "$?" "refuses a blank reference"
drop_repo

new_repo
mkdir -p deep/nested
cd deep/nested
"$TICKET" "ACME-1234" >/dev/null
cd "$REPO"
assert_equals "1" "$(ls .ticket deep/nested/.ticket 2>/dev/null | wc -l | tr -d ' ')" \
  "writes at the repo root when run from a subdirectory"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
