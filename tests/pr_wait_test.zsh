#!/usr/bin/env zsh
# Tests for bin/pr-wait.sh. Every case runs against a stub gh that answers with
# one pull request state per call, and stubs for open and sleep that write down
# their calls, so nothing reaches GitHub, opens a browser or waits.
#
# Usage: zsh tests/pr_wait_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WAIT="$SCRIPT_DIR/../bin/pr-wait.sh"

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

# Each argument is one answer gh gives, in order; the last repeats.
SHARED_STUBS="$(mktemp -d "${TMPDIR:-/tmp}/pr_wait_stubs.XXXXXX")"
cat > "$SHARED_STUBS/gh" <<'STUB'
#!/usr/bin/env bash
work="$(dirname "$0")/.."
count=$(( $(cat "$work/count" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$work/count"
[ -f "$work/answers/$count" ] || count=$(cat "$work/last")
cat "$work/answers/$count"
STUB
chmod +x "$SHARED_STUBS/gh"
cat > "$SHARED_STUBS/open" <<'STUB'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$(dirname "$0")/../opened"
STUB
chmod +x "$SHARED_STUBS/open"
cat > "$SHARED_STUBS/sleep" <<'STUB'
#!/usr/bin/env bash
work="$(dirname "$0")/.."
printf '%s\n' "$*" >> "$work/slept"
[ "$(wc -l < "$work/slept")" -lt 20 ] || { echo "still waiting after 20 rounds"; kill "$PPID"; }
STUB
chmod +x "$SHARED_STUBS/sleep"

stub() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr_wait_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/answers"
  local n=0
  for answer in "$@"; do n=$((n+1)); printf '%s' "$answer" > "$WORK/answers/$n"; done
  echo "$n" > "$WORK/last"
  local name
  for name in gh open sleep; do ln -s "$SHARED_STUBS/$name" "$WORK/bin/$name"; done
  path=("$WORK/bin" $path)
}

drop_stub() {
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
}

pr() {
  jq -nc --arg state "$1" --arg checks "$2" \
    '{state: $state, url: "https://github.com/acme/widget/pull/5",
      statusCheckRollup: ($checks | split(",") | map(select(. != "") | split(":") | {name: .[0], status: "COMPLETED", conclusion: .[1]}))}'
}

echo "pr-wait.sh:"

stub "$(pr MERGED test:SUCCESS)"
assert_equals "PR #5 was merged" "$("$WAIT" acme/widget 5 2>&1 | tail -1)" "exits saying the pull request was merged"
drop_stub

stub "$(pr CLOSED test:SUCCESS)"
assert_equals "PR #5 was closed" "$("$WAIT" acme/widget 5 2>&1 | tail -1)" "exits saying the pull request was closed"
drop_stub

stub "$(pr OPEN test:SUCCESS,lint:SUCCESS)" "$(pr MERGED test:SUCCESS,lint:SUCCESS)"
"$WAIT" acme/widget 5 >/dev/null 2>&1
assert_equals "https://github.com/acme/widget/pull/5" "$(cat "$WORK/opened" 2>/dev/null)" \
  "opens the pull request in the browser once every check passes"
drop_stub

stub "$(pr OPEN test:FAILURE,lint:SUCCESS)"
output=$("$WAIT" acme/widget 5 2>&1)
assert_equals "1 CI failed on PR #5: test opened:" "$? $(printf '%s' "$output" | tail -1) opened:$(cat "$WORK/opened" 2>/dev/null)" \
  "exits naming the failed check and opens nothing when a check fails"
drop_stub

stub "$(pr OPEN test:SUCCESS)" "$(pr OPEN test:SUCCESS)" "$(pr OPEN test:SUCCESS)" "$(pr MERGED test:SUCCESS)"
output=$("$WAIT" acme/widget 5 2>&1)
assert_equals "PR #5 was merged, opened 1 time" "$(printf '%s' "$output" | tail -1), opened $(wc -l < "$WORK/opened" | tr -d ' ') time" \
  "keeps waiting after the checks pass until the merge, opening the pull request once"
drop_stub

stub "$(pr OPEN '')" "$(pr OPEN '')" "$(pr MERGED '')"
"$WAIT" acme/widget 5 >/dev/null 2>&1
assert_equals "30 30" "$(tr '\n' ' ' < "$WORK/slept" | sed 's/ $//')" "waits 30 seconds between each question to GitHub"
drop_stub

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
rm -rf "$SHARED_STUBS"
[[ $FAIL -eq 0 ]]
