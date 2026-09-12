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

new_source() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/capture_evidence_test.XXXXXX")"
  SOURCE="$WORK/repo"
  mkdir -p "$SOURCE"
  git -C "$SOURCE" init -q
  git -C "$SOURCE" config user.email test@example.com
  git -C "$SOURCE" config user.name Test
  printf 'one\ntwo\nthree\nfour\n' > "$SOURCE/quote.rb"
  git -C "$SOURCE" add quote.rb
  git -C "$SOURCE" commit -q -m first
  HEAD_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
  DRAFT="$WORK/draft.md"
  CLAIMS="$WORK/claims.json"
  printf 'The loader reads two lines.\n' > "$DRAFT"
  cat > "$WORK/gh" <<SH
#!/usr/bin/env bash
printf '%s\\t%s\\n' "$HEAD_COMMIT" "$HEAD_COMMIT"
SH
  chmod +x "$WORK/gh"
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
