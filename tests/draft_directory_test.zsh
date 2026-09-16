#!/usr/bin/env zsh
# Tests that the draft-reading rule has each scribe write its draft into a
# directory made for that run. Scribes spawned side by side share one temporary
# directory, and a draft written to a fixed name there is overwritten by the
# next scribe, which files the wrong body.
#
# Usage: zsh tests/draft_directory_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
RULE="${SCRIPT_DIR:h}/rules/draft-reading.md"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "draft-reading.md:"

if grep -qF 'mktemp -d' "$RULE"; then
  ok "has the draft written into a directory made with mktemp -d"
else
  fail "has the draft written into a directory made with mktemp -d"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
