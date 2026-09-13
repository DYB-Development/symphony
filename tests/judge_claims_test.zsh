#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
JUDGE="$SCRIPT_DIR/../bin/judge-claims.sh"
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

echo "the claim rules, on judging:"

assert_equals "yes" "$(section_named '## What the judge is given')" \
  "say what the judge sees and what it never sees"

assert_equals "yes" "$(section_named '## What the judge returns')" \
  "say the shape a verdict comes back in"

echo ""
echo "judge-claims.sh:"

"$JUDGE" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a claims file to judge"

"$JUDGE" /nonexistent/claims.json >/dev/null 2>&1
assert_equals "70" "$?" "reports a claims file it cannot read as not judged"

new_claims() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/judge_claims_test.XXXXXX")"
  SOURCE="$WORK/repo"
  mkdir -p "$SOURCE"
  git -C "$SOURCE" init -q
  git -C "$SOURCE" config user.email test@example.com
  git -C "$SOURCE" config user.name Test
  printf 'one\ntwo\nthree\nfour\n' > "$SOURCE/quote.rb"
  git -C "$SOURCE" add quote.rb
  git -C "$SOURCE" commit -q -m first
  COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
  DRAFT="$WORK/draft.md"
  CLAIMS="$WORK/claims.json"
  printf 'The loader reads two lines.\n' > "$DRAFT"
  jq -n --arg draft "$DRAFT" --arg commit "$COMMIT" '{
    draft: $draft,
    claims: [ { text: "The loader reads two lines.",
      pointer: { path: "quote.rb", from: 2, to: 3, side: "RIGHT" },
      captured: { commit: $commit, lines: "two\nthree" } } ]
  }' > "$CLAIMS"
  cat > "$WORK/claude" <<'SH'
#!/usr/bin/env bash
here="$(dirname "$0")"
printf '%s\n' "$@" > "$here/args"
cat > "$here/stdin"
printf '%s\n' "${JUDGE_REPLY:-Standing: 0}"
exit "${JUDGE_EXIT:-0}"
SH
  chmod +x "$WORK/claude"
}

drop_claims() {
  rm -rf "$WORK"
}

judge() {
  (cd "$SOURCE" && PATH="$WORK:$PATH" "$JUDGE" "$CLAIMS")
}

new_claims
judge >/dev/null 2>&1
assert_equals "two
three" "$(awk '/^Lines captured/{on=1; next} /^File/{on=0} on && NF' "$WORK/stdin" | head -2)" \
  "hands the judge the lines captured for a claim"
drop_claims

new_claims
JUDGE_REPLY='1. "The loader reads two lines."
   Verdict: refuted
   Why: the lines read three and four, not two.

Standing: 1' judge >/dev/null 2>&1
assert_equals "refuted" "$(jq -r '.claims[0].verdict.stands' "$CLAIMS" 2>/dev/null)" \
  "writes each verdict beside the evidence it was judged against"
drop_claims

new_claims
JUDGE_REPLY='I had a look and it all seems fine to me.' judge >/dev/null 2>&1
assert_equals "70" "$?" "reports a reply it cannot read as not judged"
drop_claims

new_claims
JUDGE_EXIT=1 judge >/dev/null 2>&1
assert_equals "70" "$?" "reports a judge run that failed as not judged, never as clean"
drop_claims

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
