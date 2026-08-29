#!/usr/bin/env zsh
# Tests for claude/bin/review-draft.sh. Every case runs against a draft file
# written into a throwaway directory, and nothing here touches the network.
#
# Usage: zsh zsh/review_draft_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
DRAFT="$SCRIPT_DIR/../bin/review-draft.sh"

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

write_draft() {
  DRAFT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_draft_test.XXXXXX")"
  DRAFT_FILE="$DRAFT_DIR/review.json"
  cat > "$DRAFT_FILE"
}

drop_draft() {
  rm -rf "$DRAFT_DIR"
}

echo "review-draft.sh --render:"

write_draft <<'JSON'
{ "summary": "Four findings, one blocking.", "comments": [], "replies": [] }
JSON
assert_equals "Four findings, one blocking." \
  "$("$DRAFT" --render "$DRAFT_FILE" | sed -n 3p)" \
  "prints the summary comment the review leads with"
drop_draft

write_draft <<'JSON'
{
  "summary": "Four findings, one blocking.",
  "comments": [
    { "path": "app/models/quote.rb", "line": 42, "side": "RIGHT", "body": "Scalability - this loads a row per line item." }
  ],
  "replies": []
}
JSON
assert_equals "Inline comments (1)

1. app/models/quote.rb:42
   Scalability - this loads a row per line item." \
  "$("$DRAFT" --render "$DRAFT_FILE" | sed -n '5,8p')" \
  "prints each inline comment under the line it lands on"
drop_draft

write_draft <<'JSON'
{
  "summary": "Nothing new to raise.",
  "comments": [],
  "replies": [
    { "in_reply_to": 2145566, "body": "Moved the lookup out of the loop." }
  ]
}
JSON
assert_equals "Replies (1)

1. in reply to comment 2145566
   Moved the lookup out of the loop." \
  "$("$DRAFT" --render "$DRAFT_FILE" | sed -n '7,10p')" \
  "prints each reply beside the comment it answers"
drop_draft

write_draft <<'JSON'
{
  "summary": "One finding.",
  "comments": [
    { "path": "app/models/quote.rb", "line": 42, "side": "RIGHT", "body": "Scalability - one query per row.\n\nPreload the association." }
  ],
  "replies": []
}
JSON
assert_equals "   Scalability - one query per row.

   Preload the association." \
  "$("$DRAFT" --render "$DRAFT_FILE" | sed -n '8,10p')" \
  "leaves no trailing space on a blank line inside a comment"
drop_draft

echo ""
echo "review-draft.sh --link:"

write_draft <<'JSON'
{
  "summary": "Scalability: [the line item loop]({{comment:1}}). Security: [the team filter]({{comment:2}}).",
  "comments": [],
  "replies": []
}
JSON
assert_equals "Scalability: [the line item loop](https://github.com/o/r/pull/1#discussion_r1). Security: [the team filter](https://github.com/o/r/pull/1#discussion_r2)." \
  "$("$DRAFT" --link "$DRAFT_FILE" https://github.com/o/r/pull/1#discussion_r1 https://github.com/o/r/pull/1#discussion_r2)" \
  "points each summary finding at the comment that raised it"
drop_draft

write_draft <<'JSON'
{
  "summary": "Scalability: [the line item loop]({{comment:1}}). Security: [the team filter]({{comment:2}}).",
  "comments": [],
  "replies": []
}
JSON
"$DRAFT" --link "$DRAFT_FILE" https://github.com/o/r/pull/1#discussion_r1 >/dev/null 2>&1
assert_equals "65" "$?" \
  "refuses a summary naming a comment that was never posted"
drop_draft

echo ""
echo "review-draft.sh --post:"

stub_gh() {
  STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_draft_gh.XXXXXX")"
  GH_LOG="$STUB_DIR/calls"
  : > "$GH_LOG"
  cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$*" in *"--input -"*) cat >/dev/null 2>&1 ;; esac
case "$*" in
  *"reviews -X POST"*) printf '4242\n' ;;
  *"/comments --paginate"*) : ;;
  *) printf 'https://github.com/o/r/pull/1#x\n' ;;
esac
STUB
  chmod +x "$STUB_DIR/gh"
  export GH_LOG
  PATH="$STUB_DIR:$PATH"
}

drop_gh() {
  PATH="${PATH#*:}"
  rm -rf "$STUB_DIR"
  unset GH_LOG STUB_DIR
}

write_draft <<'JSON'
{ "summary": "Nothing to raise.", "comments": [], "replies": [] }
JSON
stub_gh
( "$DRAFT" --post o/r 1 "$DRAFT_FILE" >/dev/null 2>&1 & pid=$!
  ( sleep 10; kill -9 $pid 2>/dev/null ) & watch=$!
  wait $pid 2>/dev/null; kill $watch 2>/dev/null )
assert_equals "0" \
  "$(grep -c 'replies' "$GH_LOG" | tr -d ' ')" \
  "posts no reply when the draft carries none"
drop_gh
drop_draft

write_draft <<'JSON'
{
  "summary": "Two threads answered.",
  "comments": [],
  "replies": [
    { "in_reply_to": 111, "body": "Preloaded in 3a1f2c9." },
    { "in_reply_to": 222, "body": "Left as is, and here is why." }
  ]
}
JSON
stub_gh
( "$DRAFT" --post o/r 1 "$DRAFT_FILE" >/dev/null 2>&1 & pid=$!
  ( sleep 10; kill -9 $pid 2>/dev/null ) & watch=$!
  wait $pid 2>/dev/null; kill $watch 2>/dev/null )
assert_equals "111
222" \
  "$(grep -o 'comments/[0-9]*/replies' "$GH_LOG" | sed 's|comments/||; s|/replies||')" \
  "posts one reply to each thread the draft answers"
drop_gh
drop_draft

echo ""
echo "review-draft.sh usage:"

write_draft <<'JSON'
{ "summary": "Nothing to raise.", "comments": [], "replies": [] }
JSON
"$DRAFT" --summarise "$DRAFT_FILE" >/dev/null 2>&1
assert_equals "64" "$?" "exits with a usage code when the mode is not one it has"
drop_draft

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
