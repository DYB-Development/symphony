#!/usr/bin/env zsh
# Tests for bin/review-started.sh. Every case runs against a stub gh that serves
# one head commit and writes down each comment it is asked to post, so nothing
# reaches GitHub.
#
# Usage: zsh tests/review_started_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STARTED="$SCRIPT_DIR/../bin/review-started.sh"

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

# A gh that serves the head commit of pull request 7 of acme/widget and keeps
# each comment body it is asked to post in $WORK/posted.
SHARED_STUBS="$(mktemp -d "${TMPDIR:-/tmp}/review_started_stubs.XXXXXX")"
cat > "$SHARED_STUBS/gh" <<'STUB'
#!/usr/bin/env bash
work="$(dirname "$0")/.."
case "$*" in
  "pr view 7 --repo acme/widget --json headRefOid --jq .headRefOid")
    [ -f "$work/unreadable" ] && exit 1
    echo "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678" ;;
  "pr comment 7 --repo acme/widget --body "*)
    [ -f "$work/unreadable" ] && exit 1
    printf '%s\n' "$7" >> "$work/posted"
    echo "https://github.com/acme/widget/pull/7#issuecomment-1" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$SHARED_STUBS/gh"

stub_gh() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/review_started_test.XXXXXX")"
  mkdir "$WORK/bin"
  ln -s "$SHARED_STUBS/gh" "$WORK/bin/gh"
}

drop_gh() {
  rm -rf "$WORK"
}

echo "review-started.sh:"

stub_gh
PATH="$WORK/bin:$PATH" "$STARTED" acme/widget 7 >/dev/null 2>&1
assert_equals "Review started against a1b2c3d." "$(cat "$WORK/posted" 2>/dev/null)" \
  "posts one comment naming the head commit the review reads"
drop_gh

stub_gh
touch "$WORK/unreadable"
assert_equals "review-started.sh: the head commit of acme/widget#7 could not be read, so nothing was posted" \
  "$(PATH="$WORK/bin:$PATH" "$STARTED" acme/widget 7 2>&1 >/dev/null)" \
  "says nothing was posted when the head commit cannot be read"
drop_gh

rm -rf "$SHARED_STUBS"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
