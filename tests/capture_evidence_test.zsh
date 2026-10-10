#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
CAPTURE="$SCRIPT_DIR/../bin/capture-evidence.sh"
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

section_named() {
  awk -v want="$1" '$0 == want { found = 1 } END { print found ? "yes" : "no" }' "$RULES"
}

echo "the claim rules, written around pointers:"

assert_equals "yes" "$(section_named '## What a claim pointer holds')" \
  "say what a scribe writes for one claim"

echo ""
echo "capture-evidence.sh:"

"$CAPTURE" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a claims file and a pull request"

"$CAPTURE" /nonexistent/claims.json acme/quotes 7 >/dev/null 2>&1
assert_equals "70" "$?" "reports a claims file it cannot read as not captured"

TEMPLATE="$(mktemp -d "${TMPDIR:-/tmp}/capture_evidence_template.XXXXXX")"
git -C "$TEMPLATE" init -q --template= repo
git -C "$TEMPLATE/repo" config user.email test@example.com
git -C "$TEMPLATE/repo" config user.name Test
printf 'one\ntwo\nthree\nfour\n' > "$TEMPLATE/repo/quote.rb"
git -C "$TEMPLATE/repo" add quote.rb
git -C "$TEMPLATE/repo" commit -q -m first
cat > "$TEMPLATE/gh" <<'SH'
#!/usr/bin/env bash
here="$(dirname "$0")"
[ ! -f "$here/gh_fails" ] || exit 1
cat "$here/gh_reply"
SH
chmod +x "$TEMPLATE/gh"
"$TEMPLATE/gh" >/dev/null 2>&1

answer_pull_request() {
  printf '%s\t%s\n' "$1" "$2" > "$WORK/gh_reply"
}

new_source() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/capture_evidence_test.XXXXXX")"
  SOURCE="$WORK/repo"
  cp -R "$TEMPLATE/repo" "$SOURCE"
  HEAD_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
  DRAFT="$WORK/draft.md"
  CLAIMS="$WORK/claims.json"
  printf 'The loader reads two lines.\n' > "$DRAFT"
  ln -s "$TEMPLATE/gh" "$WORK/gh"
  answer_pull_request "$HEAD_COMMIT" "$HEAD_COMMIT"
}

drop_source() {
  rm -rf "$WORK"
}

write_pointer() {
  jq -n --arg draft "$DRAFT" --argjson from "$1" --argjson to "$2" --arg path "${3:-quote.rb}" '{
    draft: $draft,
    claims: [ { text: "The loader reads two lines.", pointer: { path: $path, from: $from, to: $to, side: "RIGHT" } } ]
  }' > "$CLAIMS"
}

capture() {
  (cd "$SOURCE" && PATH="$WORK:$PATH" "$CAPTURE" "$CLAIMS" acme/quotes 7)
}

new_source
write_pointer 2 3
capture >/dev/null 2>&1
assert_equals "two
three" "$(jq -r '.claims[0].captured.lines' "$CLAIMS" 2>/dev/null)" \
  "records the lines a pointer names, read at that side's commit"
drop_source

new_source
write_pointer 2 3
capture >/dev/null 2>&1
assert_equals "$HEAD_COMMIT" "$(jq -r '.claims[0].captured.commit' "$CLAIMS" 2>/dev/null)" \
  "records the full commit each pointer was read at"
drop_source

new_source
write_pointer 1 1 gone.rb
capture >/dev/null 2>&1
assert_equals "1" "$?" "reports a pointer naming a file that is not at that commit as unresolved"
drop_source

new_source
write_pointer 9 12
capture >/dev/null 2>&1
assert_equals "1" "$?" "reports a line range the file does not reach as unresolved"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [ { text: "The loader reads two lines.",
    pointer: { path: "quote.rb", from: 2, to: 3, side: "RIGHT", quote: "two\nthree" } } ]
}' > "$CLAIMS"
capture >/dev/null 2>&1
assert_equals "1" "$?" "rejects a pointer carrying a quote, a commit or any line content"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{ draft: $draft, claims: [ { text: "The loader reads two lines." } ] }' > "$CLAIMS"
capture >/dev/null 2>&1
assert_equals "1" "$?" "reports a claim with no pointer as failing"
drop_source

new_source
jq -n --arg draft "$DRAFT" '{
  draft: $draft,
  claims: [ { text: "The loader reads nine lines.",
    pointer: { path: "quote.rb", from: 2, to: 3, side: "RIGHT" } } ]
}' > "$CLAIMS"
capture >/dev/null 2>&1
assert_equals "1" "$?" "reports a claim whose text is not in the draft as failing"
drop_source

new_source
write_pointer 2 3
touch "$WORK/gh_fails"
capture >/dev/null 2>&1
assert_equals "70" "$?" "reports a pull request it cannot read as not captured"
drop_source

new_source
FORK="$WORK/fork"
git clone -q "$SOURCE" "$FORK"
printf 'one\ntwo\nthree\nfour\nfive\n' > "$FORK/quote.rb"
git -C "$FORK" add quote.rb
git -C "$FORK" -c user.email=t@e.com -c user.name=T commit -q -m second
FORK_COMMIT="$(git -C "$FORK" rev-parse HEAD)"
answer_pull_request "$FORK_COMMIT" "$HEAD_COMMIT"
git -C "$SOURCE" remote add fork "$FORK" 2>/dev/null
write_pointer 5 5
capture >/dev/null 2>&1
assert_equals "five" "$(jq -r '.claims[0].captured.lines' "$CLAIMS" 2>/dev/null)" \
  "downloads a commit the clone does not have, then reads it"
drop_source

new_source
write_pointer 2 3
capture >/dev/null 2>&1
assert_equals "0" "$?" "exits 0 when every pointer resolves"
drop_source

new_source
write_pointer 3 12
capture >/dev/null 2>&1
code=$?
[[ $code -eq 1 && "$(jq -r '.claims[0].captured // "none"' "$CLAIMS")" == "none" ]]
assert_equals "0" "$?" "reports a range that overruns the end of the file as unresolved"
drop_source

new_source
mkdir -p "$SOURCE/app/models"
printf 'class Quote\nend\n' > "$SOURCE/app/models/quote.rb"
git -C "$SOURCE" add app/models/quote.rb
git -C "$SOURCE" commit -q -m "add a directory"
HEAD_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
answer_pull_request "$HEAD_COMMIT" "$HEAD_COMMIT"
write_pointer 1 1 app/models
capture >/dev/null 2>&1
code=$?
[[ $code -eq 1 && "$(jq -r '.claims[0].captured // "none"' "$CLAIMS")" == "none" ]]
assert_equals "0" "$?" "reports a pointer naming a directory as unresolved"
drop_source

rm -rf "$TEMPLATE"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
