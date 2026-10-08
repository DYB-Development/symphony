#!/usr/bin/env zsh
# Tests for bin/pr-state.sh. Every case runs against a stub gh that prints one
# pull request, so nothing reaches GitHub.
#
# Usage: zsh tests/pr_state_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STATE="$SCRIPT_DIR/../bin/pr-state.sh"

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

# One pull request in the state given, with checks written as name:conclusion,...
stub() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr_state_test.XXXXXX")"
  mkdir -p "$WORK/bin"
  jq -nc --arg state "$1" --arg checks "$2" \
    '{state: $state, url: "https://github.com/acme/quotes/pull/5", number: 5,
      statusCheckRollup: ($checks | split(",") | map(select(. != "") | split(":") | {name: .[0], conclusion: .[1]}))}' > "$WORK/answer"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/calls"\ncat "%s/answer"\n' "$WORK" "$WORK" > "$WORK/bin/gh"
  chmod +x "$WORK/bin/gh"
  path=("$WORK/bin" $path)
}

drop_stub() {
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
}

echo "pr-state.sh:"

stub OPEN "tests:SUCCESS,lint:SUCCESS"
assert_equals "OPEN	https://github.com/acme/quotes/pull/5	5	passed" "$("$STATE" 7-export-quotes)" \
  "prints the state, address, number and passed for an open pull request whose checks all passed"
drop_stub

stub OPEN "tests:FAILURE,lint:SUCCESS,deploy:CANCELLED"
assert_equals "OPEN	https://github.com/acme/quotes/pull/5	5	failed: tests, deploy" "$("$STATE" 5)" \
  "names each check that failed, was cancelled or timed out"
drop_stub

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
