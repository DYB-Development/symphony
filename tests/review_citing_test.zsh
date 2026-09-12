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

assert_names 'a side' "names which side of the diff a pointer reads"

assert_names 'Every Findings bullet that reports a finding' "cites the lines behind each Findings bullet that reports a finding"

assert_names '~/.claude/bin/capture-evidence.sh' "has the tooling read the lines before the draft goes back"

assert_names 'A finding whose pointer cannot be resolved is cut from the draft.' "cuts a finding whose pointer cannot be resolved"

assert_names 'Removed for a failed citation:' "names each claim it cut for a failed citation"

assert_names "Every inline comment has a claim whose pointer is that comment's own path, line and side." "points each finding at the lines its comment already names"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
