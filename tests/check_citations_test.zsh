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

assert_equals "yes" "$(section_named '## How a criterion citation is written')" \
  "say how a citation to a ticket criterion is written"

assert_equals "yes" "$(section_named '## How a command citation is written')" \
  "say how a citation to a command and its output is written"

assert_equals "yes" "$(section_named '## How a link citation is written')" \
  "say how a citation to a page is written"

assert_equals "yes" "$(section_named '## What a negative claim rests on')" \
  "say what evidence a negative claim rests on"

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

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "lines", repo: "acme/quotes", commit: "0000000000000000000000000000000000000000", path: "quote.rb", from: 2, to: 3, quote: "two\nthree" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "70" "$?" "reports a cited commit it cannot read as not checked"
drop_source

new_source
cat > "$WORK/gh" <<'SH'
#!/usr/bin/env bash
printf 'A rep can convert a quote.\nA rep can print a quote.\n'
SH
chmod +x "$WORK/gh"
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "criterion", ticket: "acme/quotes#7", quote: "A rep can delete a quote." } ] }
  ]
}' > "$LEDGER"
(cd "$SOURCE" && PATH="$WORK:$PATH" "$CHECK" "$LEDGER") >/dev/null 2>&1
assert_equals "1" "$?" "fails a criterion that is not in the cited ticket"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "command", run: "grep -c two quote.rb", output: "5" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a command whose output differs from the output recorded"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "command", run: "touch written.txt", output: "" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
code=$?
[[ $code -eq 1 && ! -e "$SOURCE/written.txt" ]]
assert_equals "0" "$?" "refuses a command that is not a reader, and never runs it"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "command", run: "bun test tests/loader.test.ts", output: "2 pass" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "refuses a command that runs the code or its tests as evidence"
drop_source

new_source
cat > "$WORK/curl" <<'SH'
#!/usr/bin/env bash
[ "${CURL_EXIT:-0}" = 0 ] || exit "$CURL_EXIT"
printf 'The page says something else entirely.\n'
SH
chmod +x "$WORK/curl"
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "link", url: "https://example.com/doc", quote: "the loader reads two lines" } ] }
  ]
}' > "$LEDGER"
(cd "$SOURCE" && PATH="$WORK:$PATH" "$CHECK" "$LEDGER") >/dev/null 2>&1
assert_equals "1" "$?" "fails a link whose page no longer holds the quoted text"
drop_source

new_source
cat > "$WORK/curl" <<'SH'
#!/usr/bin/env bash
exit 7
SH
chmod +x "$WORK/curl"
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: false,
      evidence: [ { kind: "link", url: "https://example.com/doc", quote: "the loader reads two lines" } ] }
  ]
}' > "$LEDGER"
(cd "$SOURCE" && PATH="$WORK:$PATH" "$CHECK" "$LEDGER") >/dev/null 2>&1
assert_equals "70" "$?" "reports a link it could not fetch as not checked"
drop_source

new_source
write_ledger 'two
three' 2 3
jq '.claims[0].negative = true' "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a negative claim that rests on anything but a search"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [
    { text: "The loader reads two lines.", negative: true,
      evidence: [ { kind: "search", looked_for: "any mention of three", run: "grep -n three quote.rb", output: "" } ] }
  ]
}' > "$LEDGER"
check >/dev/null 2>&1
assert_equals "1" "$?" "fails a negative claim whose search now finds something"
drop_source

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
