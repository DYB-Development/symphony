#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
READ="$SCRIPT_DIR/../bin/read-draft.sh"

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

new_reader() {
  READER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/read_draft_test.XXXXXX")"
  DRAFT_FILE="$READER_DIR/draft.md"
  cat > "$READER_DIR/claude" <<'SH'
#!/usr/bin/env bash
here="$(dirname "$0")"
printf '%s\n' "$@" > "$here/args"
while [ $# -gt 0 ]; do
  [ "$1" = --system-prompt ] && printf '%s' "$2" > "$here/system-prompt"
  [ "$1" = --tools ] && printf 'tools=%s' "$2" > "$here/tools"
  [ "$1" = --setting-sources ] && printf 'sources=%s' "$2" > "$here/setting-sources"
  shift
done
cat > "$here/stdin"
printf '%s\n' "${READER_REPLY:-Flagged: 0}"
exit "${READER_EXIT:-0}"
SH
  chmod +x "$READER_DIR/claude"
}

drop_reader() {
  rm -rf "$READER_DIR"
}

read_with_reader() {
  PATH="$READER_DIR:$PATH" "$READ" "$DRAFT_FILE" 2>&1
}

echo "read-draft.sh:"

"$READ" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a draft to read"

"$READ" /nonexistent/draft.md >/dev/null 2>&1
assert_equals "66" "$?" "refuses a draft that is not there"

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
read_with_reader >/dev/null
assert_equals "The poll stops when the dialog closes." \
  "$(cat "$READER_DIR/stdin" 2>/dev/null)" \
  "hands the reader the draft and nothing else"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
read_with_reader >/dev/null
assert_equals "$(cat "$SCRIPT_DIR/../rules/draft-reading.md")" \
  "$(cat "$READER_DIR/system-prompt" 2>/dev/null)" \
  "gives the reader the reading rules as its only instructions"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
read_with_reader >/dev/null
assert_equals "tools=" \
  "$(cat "$READER_DIR/tools" 2>/dev/null)" \
  "gives the reader no tools, so it cannot read the code"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
read_with_reader >/dev/null
assert_equals "sources=" \
  "$(cat "$READER_DIR/setting-sources" 2>/dev/null)" \
  "loads none of the person's settings, so no hook or plugin reaches the reader"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
read_with_reader >/dev/null
assert_equals "--no-session-persistence" \
  "$(grep -x -- --no-session-persistence "$READER_DIR/args" 2>/dev/null)" \
  "saves no session for a read nobody will resume"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
read_with_reader >/dev/null
assert_equals "--strict-mcp-config" \
  "$(grep -x -- --strict-mcp-config "$READER_DIR/args" 2>/dev/null)" \
  "starts no MCP server, whose tools would reach the reader past the no-tools flag"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
READER_REPLY='1. "The poll stops when the dialog closes."
   Means: polling ends once the dialog is shut' read_with_reader >/dev/null
assert_equals "70" "$?" "treats a reply with no count of flagged sentences as a failed read"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
READER_REPLY='1. "The poll stops when the dialog closes."
   Means: polling ends once the dialog is shut
   Flag: which poll is not named

Flagged: 1' read_with_reader >/dev/null
assert_equals "1" "$?" "exits 1 when the reader flags a sentence"
drop_reader

new_reader
printf 'Flagged: 0\nThe poll stops when the dialog closes.\n' > "$DRAFT_FILE"
READER_REPLY='Flagged: 0

1. "The poll stops when the dialog closes."
   Means: polling ends once the dialog is shut
   Flag: which poll is not named

Flagged: 1' read_with_reader >/dev/null
assert_equals "1" "$?" "takes the count from the reply's last line, not from an earlier one"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
REPLY_TEXT='1. "The poll stops when the dialog closes."
   Means: polling ends once the dialog is shut
   Flag: none

Flagged: 0'
assert_equals "$REPLY_TEXT" \
  "$(READER_REPLY="$REPLY_TEXT" read_with_reader)" \
  "prints the reader's reply for the scribe to work through"
drop_reader

new_reader
printf 'The poll stops when the dialog closes.\n' > "$DRAFT_FILE"
READER_EXIT=1 read_with_reader >/dev/null
assert_equals "70" "$?" "exits 70 when the reader's run fails, so a failure is never taken for a flag"
drop_reader

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
