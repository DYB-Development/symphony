#!/usr/bin/env zsh
# Tests for bin/issue-bootstrap.sh. Nothing here reaches the network: the cases
# that would call gh run only the argument handling in front of it.
#
# Usage: zsh tests/issue_bootstrap_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
BOOTSTRAP="$SCRIPT_DIR/../bin/issue-bootstrap.sh"

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

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

# A stub gh on PATH, so a case that gets past the guard cannot reach the
# network. --all-repos writes labels to every repo of every account it is
# given, and a test must never be the thing that does that.
STUB="$(mktemp -d "${TMPDIR:-/tmp}/issue_bootstrap_test.XXXXXX")"
cat > "$STUB/gh" <<'GH'
#!/usr/bin/env bash
echo "STUB GH CALLED: $*" >&2
exit 0
GH
chmod +x "$STUB/gh"
PATH="$STUB:$PATH"

echo "issue-bootstrap.sh accounts:"

ISSUE_BOOTSTRAP_OWNERS="" "$BOOTSTRAP" --all-repos >/dev/null 2>&1
assert_equals "78" "$?" "refuses to sync every repo when no account is configured"

assert_contains \
  "ISSUE_BOOTSTRAP_OWNERS" \
  "$(ISSUE_BOOTSTRAP_OWNERS="" "$BOOTSTRAP" --all-repos 2>&1)" \
  "names the variable that says whose repos to sync"

assert_equals \
  "" \
  "$(grep -oE '^OWNERS=\([a-zA-Z]' "$BOOTSTRAP")" \
  "hardcodes no account of its own"

echo ""
echo "issue-bootstrap.sh arguments:"

"$BOOTSTRAP" --no-such-flag >/dev/null 2>&1
assert_equals "64" "$?" "refuses an argument it does not recognise"

assert_contains "--no-such-flag" \
  "$("$BOOTSTRAP" --no-such-flag 2>&1)" \
  "names the argument it refused"

"$BOOTSTRAP" --help >/dev/null 2>&1
assert_equals "0" "$?" "prints help without failing"

assert_contains "--all-repos" \
  "$("$BOOTSTRAP" --help 2>&1)" \
  "names its flags in the help"

assert_equals "" \
  "$("$BOOTSTRAP" --help 2>&1 >/dev/null | grep -o 'STUB GH CALLED' || true)" \
  "calls nothing outside itself while printing help"

assert_equals "78" \
  "$(ISSUE_BOOTSTRAP_OWNERS="" "$BOOTSTRAP" --all-repos >/dev/null 2>&1; echo $?)" \
  "leaves a flag it already recognised behaving as it did"

assert_contains "STUB GH CALLED" \
  "$("$BOOTSTRAP" --labels-only 2>&1)" \
  "still bootstraps when given a flag it recognises"

assert_contains "STUB GH CALLED" \
  "$("$BOOTSTRAP" 2>&1)" \
  "still bootstraps the current repo with no argument"

rm -rf "$STUB"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
