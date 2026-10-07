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
stub() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr_wait_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/answers"
  local n=0
  for answer in "$@"; do n=$((n+1)); printf '%s' "$answer" > "$WORK/answers/$n"; done
  cat > "$WORK/bin/gh" <<STUB
#!/usr/bin/env bash
count=\$(( \$(cat "$WORK/count" 2>/dev/null || echo 0) + 1 ))
echo "\$count" > "$WORK/count"
[ -f "$WORK/answers/\$count" ] || count=$n
cat "$WORK/answers/\$count"
STUB
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/opened"\n' "$WORK" > "$WORK/bin/open"
  cat > "$WORK/bin/sleep" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/slept"
[ "\$(wc -l < "$WORK/slept")" -lt 20 ] || { echo "still waiting after 20 rounds"; kill "\$PPID"; }
STUB
  chmod +x "$WORK/bin/"*
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

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
