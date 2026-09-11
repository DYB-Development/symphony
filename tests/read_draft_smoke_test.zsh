#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
READ="$SCRIPT_DIR/../bin/read-draft.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m–\033[0m %s\n' "$1"; }

echo "read-draft.sh against a real reader:"

if [[ "${READ_DRAFT_SMOKE:-}" != 1 ]]; then
  skip "READ_DRAFT_SMOKE is not 1, so no reader is run"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  exit 0
fi

DRAFT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/read_draft_smoke_test.XXXXXX")"
printf 'This cannot merge until the portal keeps asking whether the signature landed after the dialog closes.\n' > "$DRAFT_DIR/draft.md"

"$READ" "$DRAFT_DIR/draft.md"
code=$?

if [[ $code -eq 0 || $code -eq 1 ]]; then
  ok "a real reader returns a reply the script can count"
else
  fail "a real reader returns a reply the script can count"
  printf '      exit: %s\n' "$code"
fi

rm -rf "$DRAFT_DIR"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
