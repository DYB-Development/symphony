#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CHECK="$SCRIPT_DIR/../bin/check-citations.sh"
RULES="$SCRIPT_DIR/../rules/claim-checking.md"

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

echo "the claim checking rules:"

section_named() {
  awk -v want="$1" '$0 == want { found = 1 } END { print found ? "yes" : "no" }' "$RULES"
}

assert_equals "yes" "$(section_named '## What counts as a claim')" \
  "say what counts as a factual claim"

echo ""
echo "check-citations.sh:"

"$CHECK" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a ledger to check"

"$CHECK" /nonexistent/ledger.json >/dev/null 2>&1
assert_equals "70" "$?" "reports a ledger it cannot read as not checked"

new_source() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/check_citations_test.XXXXXX")"
  SOURCE="$WORK/repo"
  mkdir -p "$SOURCE"
  git -C "$SOURCE" init -q
  git -C "$SOURCE" config user.email test@example.com
  git -C "$SOURCE" config user.name Test
  printf 'one\ntwo\nthree\nfour\n' > "$SOURCE/quote.rb"
  git -C "$SOURCE" add quote.rb
  git -C "$SOURCE" commit -q -m "first"
  COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
  DRAFT="$WORK/draft.md"
  LEDGER="$WORK/ledger.json"
  printf 'The loader reads two lines.\n' > "$DRAFT"
}

drop_source() {
  rm -rf "$WORK"
}

write_ledger() {
  jq -n --arg draft "$DRAFT" --arg commit "$COMMIT" --arg quote "$1" --argjson from "$2" --argjson to "$3" '{
    draft: $draft,
    claims: [
      { text: "The loader reads two lines.", negative: false,
        evidence: [ { kind: "lines", repo: "acme/quotes", commit: $commit, path: "quote.rb", from: $from, to: $to, quote: $quote } ] }
    ]
  }' > "$LEDGER"
}

check() {
  (cd "$SOURCE" && "$CHECK" "$LEDGER")
}

new_source
write_ledger 'two
three' 2 3
check >/dev/null 2>&1
assert_equals "0" "$?" "passes a quote that matches those lines at the cited commit"
drop_source

new_source
write_ledger 'two
threex' 2 3
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a quote that differs from those lines by one character"
drop_source

new_source
jq -n --arg draft "$DRAFT" --arg commit "$COMMIT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "lines", repo: "acme/quotes", commit: $commit, path: "gone.rb", from: 1, to: 1, quote: "" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a citation to a file that is not at the cited commit"
drop_source

new_source
jq -n --arg draft "$DRAFT" --arg commit "$COMMIT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads three lines.", negative: false,
      evidence: [ { kind: "lines", repo: "acme/quotes", commit: $commit, path: "quote.rb", from: 2, to: 3, quote: "two\nthree" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a claim whose text is not in the draft word for word"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [ { text: "The loader reads two lines.", negative: false, evidence: [] } ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a claim that carries no evidence"
drop_source

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
