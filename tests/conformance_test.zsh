#!/usr/bin/env zsh
# Tests for bin/conformance.sh. Each case runs against a stubbed `gh` that
# answers from files written for the case, and a stubbed `claude`.
#
# Usage: zsh tests/conformance_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CONFORMANCE="$SCRIPT_DIR/../bin/conformance.sh"

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

new_case() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/conformance_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/repo"
  : > "$WORK/ticket"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr view") cat "$WORK/ticket" ;;
  "issue view") cat "$WORK/issue" ;;
esac
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/bin/claude" <<SH
#!/usr/bin/env bash
cat >> "$WORK/asked"
printf '%s\n' "\${CLAUDE_REPLY:-1: none}"
SH
  chmod +x "$WORK/bin/claude"
  DRAFT_FILE="$WORK/repo/.review-7.json"
  printf '{ "tests": [], "hits": [] }\n' > "$WORK/repo/.review-7.tests.json"
  RESULT="$WORK/repo/.review-7.conformance.json"
}

drop_case() {
  rm -rf "$WORK"
}

conformance() {
  PATH="$WORK/bin:$PATH" SYMPHONY_AGENT_MODELS_FILE="$WORK/no-models.json" "$CONFORMANCE" acme/quotes 7 "$DRAFT_FILE"
}

render() {
  "$CONFORMANCE" --render "$RESULT"
}

echo "conformance.sh:"

new_case
conformance >/dev/null 2>&1
assert_equals "No ticket referenced." "$(render 2>&1)" \
  "reports that no ticket was referenced when the pull request names none"
drop_case

with_ticket() {
  printf '12\n' > "$WORK/ticket"
  cat > "$WORK/issue" <<'MD'
**As a** rep, **I want** a quote total.

## Acceptance criteria
- [ ] A rep sees the quote total on the quote page.

## Out of scope
- Taxes.
MD
}

valid_test() {
  jq -n --arg title "$1" '{ tests: [ { path: "test/quote_test.rb", line: 2, title: $title, assertions: 1 } ], hits: [] }' \
    > "$WORK/repo/.review-7.tests.json"
}

new_case
with_ticket
valid_test "shows the quote total on the quote page"
CLAUDE_REPLY="1: 1" conformance >/dev/null 2>&1
assert_equals '- [x] A rep sees the quote total on the quote page. Covered by "shows the quote total on the quote page".' \
  "$(render 2>&1)" \
  "ticks a criterion a valid test covers and names the test"
drop_case

new_case
with_ticket
valid_test "sums the line items into the total"
CLAUDE_REPLY="1: none" conformance >/dev/null 2>&1
assert_equals '- [ ] A rep sees the quote total on the quote page. No valid test covers it.' \
  "$(render 2>&1)" \
  "leaves a criterion no valid test covers unticked and says so"
drop_case

new_case
with_ticket
jq -n '{ tests: [ { path: "test/quote_test.rb", line: 2, title: "shows the quote total on the quote page", assertions: 3 } ],
  hits: [ { path: "test/quote_test.rb", line: 2, pattern: "test-asserts-more-than-one-thing", check: "Tests" } ] }' \
  > "$WORK/repo/.review-7.tests.json"
conformance >/dev/null 2>&1
assert_equals "0" "$(grep -c 'shows the quote total' "$WORK/asked" 2>/dev/null)" \
  "never offers the model a test the inventory found a fault in"
drop_case

new_case
with_ticket
valid_test "shows the quote total on the quote page"
conformance >/dev/null 2>&1
assert_equals "yes yes no no" \
  "$(grep -q 'A rep sees the quote total' "$WORK/asked" && echo yes || echo no) $(grep -q 'shows the quote total on the quote page' "$WORK/asked" && echo yes || echo no) $(grep -q 'Taxes' "$WORK/asked" && echo yes || echo no) $(grep -q 'I want' "$WORK/asked" && echo yes || echo no)" \
  "gives the model the acceptance criteria and test titles and nothing else from the ticket"
drop_case

new_case
with_ticket
valid_test "shows the quote total on the quote page"
CLAUDE_REPLY="The first test covers it." conformance >/dev/null 2>&1
assert_equals "70" "$?" "fails when the model's reply does not end in a criterion line"
drop_case

new_case
with_ticket
rm "$WORK/repo/.review-7.tests.json"
printf '{ "ticket": 12, "criteria": [ { "text": "A rep sees the quote total on the quote page.", "covered_by": ["an old test"] } ] }\n' > "$RESULT"
assert_equals "70 no result" \
  "$(conformance >/dev/null 2>&1; echo "$? $([[ -e "$RESULT" ]] && echo "result left" || echo "no result")")" \
  "stops and ticks no criterion when the test judgement did not finish"
drop_case

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
