#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
REVIEW_SCRIBE="$SCRIPT_DIR/../agents/review-scribe.md"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_names() {
  if grep -qF -- "$1" "$REVIEW_SCRIBE"; then
    ok "$2"
  else
    fail "$2"
    printf '      review-scribe.md does not say: %s\n' "${(qqq)1}"
  fi
}

echo "the review scribe's citing step:"

assert_names '.review-<pr>.claims.json' "writes the claim ledger beside the draft"

assert_names 'at the pull request'\''s head or base commit' "cites the lines each inline comment is about"

assert_names 'Every Findings bullet that reports a finding' "cites the lines behind each Findings bullet that reports a finding"

assert_names '~/.claude/bin/check-citations.sh' "checks the ledger before the draft goes back"

assert_names 'A finding whose citation cannot be made to pass is cut from the draft.' "cuts a finding whose citation cannot pass"

assert_names 'Removed for a failed citation:' "names each claim it cut for a failed citation"

assert_names 'carries a claim whose evidence is the searches that came back empty' "cites the searches behind a bullet that found nothing"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
