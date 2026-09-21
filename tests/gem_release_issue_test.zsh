#!/usr/bin/env zsh
# Tests for bin/gem-release-issue.sh. Every case runs against a gh that records
# what it was asked to do instead of reaching GitHub.
#
# Usage: zsh tests/gem_release_issue_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
OPEN_ISSUE="$SCRIPT_DIR/../bin/gem-release-issue.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

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

assert_lacks() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      did not want:   %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

# A gh that writes down every call and answers the issue search with $MATCHES.
stub_gh() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/gem_release_issue.XXXXXX")"
  GH_LOG="$STUB_BIN/calls"
  : > "$GH_LOG"
  cat > "$STUB_BIN/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
if [[ "\$1 \$2" == "issue list" ]]; then
  printf '%s' '${1:-[]}'
fi
if [[ "\$1 \$2" == "issue create" ]]; then
  printf 'https://github.com/acme/widget/issues/1\n'
fi
if [[ "\$*" == *--body-file\ -* ]]; then
  cat >> "$GH_LOG.body"
fi
exit 0
STUB
  chmod +x "$STUB_BIN/gh"
  : > "$GH_LOG.body"
  path=("$STUB_BIN" $path)

  export GITHUB_REPOSITORY="acme/widget"
  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_RUN_ID="12345"
  export GITHUB_SHA="a1b2c3d"
}

drop_stub() {
  path=(${path:#$STUB_BIN})
  rm -rf "$STUB_BIN"
}

echo "gem-release-issue.sh:"

stub_gh
print -r -- "bundle install failed" | "$OPEN_ISSUE" widget 0.2.0 >/dev/null 2>&1
assert_contains "Release failed: widget 0.2.0" "$(cat "$GH_LOG")" "opens an issue titled with the gem and the version"
drop_stub

stub_gh
print -r -- "bundle install failed" | "$OPEN_ISSUE" widget 0.2.0 >/dev/null 2>&1
assert_contains "bundle install failed" "$(cat "$GH_LOG.body")" "carries what went wrong into the issue body"
drop_stub

stub_gh '[{"number":7,"title":"Release failed: widget 0.2.0"}]'
print -r -- "bundle install failed" | "$OPEN_ISSUE" widget 0.2.0 >/dev/null 2>&1
assert_contains "issue comment 7" "$(cat "$GH_LOG")" "comments on the open issue for this version instead of opening a second"
drop_stub

stub_gh
print -r -- "bundle install failed" | "$OPEN_ISSUE" widget 0.2.0 >/dev/null 2>&1
assert_contains "issue edit 1 --repo acme/widget --add-label release-failure" "$(cat "$GH_LOG")" "labels the issue it opened so every release failure can be listed at once"
drop_stub

stub_gh
print -r -- "bundle install failed" | "$OPEN_ISSUE" widget 0.2.0 >/dev/null 2>&1
assert_equals "0" "$(grep -cv -- "--repo acme/widget" "$GH_LOG")" \
  "names the gem's repository on every call, since the scripts are checked out from another one"
drop_stub

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
