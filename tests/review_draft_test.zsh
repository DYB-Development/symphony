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
echo "review-draft.sh --check-lines:"

new_diff() {
  LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
  LINES_FILE="$LINES_DIR/review.json"
  cat > "$LINES_DIR/gh" <<'SH'
#!/usr/bin/env bash
cat <<'DIFF'
diff --git a/app/models/quote.rb b/app/models/quote.rb
index 1111111..2222222 100644
--- a/app/models/quote.rb
+++ b/app/models/quote.rb
@@ -40,3 +40,4 @@ class Quote
   def convert
+    order.save
   end
 end
DIFF
SH
  chmod +x "$LINES_DIR/gh"
}

drop_diff() {
  rm -rf "$LINES_DIR"
}

check_lines() {
  PATH="$LINES_DIR:$PATH" "$DRAFT" --check-lines "$LINES_FILE" acme/quotes 7 2>&1
}

new_diff
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/models/quote.rb", "line": 41, "side": "RIGHT", "body": "a finding" } ],
  "replies": [] }
JSON
assert_equals "on the diff  app/models/quote.rb:41" "$(check_lines)" \
  "says an inline comment sits on a line the diff touches"
drop_diff

new_diff
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/models/quote.rb", "line": 12, "side": "RIGHT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "1" "$?" "fails an inline comment that is not on a line the diff touches"
drop_diff

new_diff
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/models/quote.rb", "line": 41, "side": "LEFT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "1" "$?" "fails a left-side comment on a line the diff does not remove"
drop_diff

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
cat > "$LINES_DIR/gh" <<'SH'
#!/usr/bin/env bash
cat <<'DIFF'
diff --git a/app/quote[1].rb b/app/quote[1].rb
--- a/app/quote[1].rb
+++ b/app/quote[1].rb
@@ -1,2 +1,3 @@
 class Quote
+  def convert; end
 end
DIFF
SH
chmod +x "$LINES_DIR/gh"
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/quote[1].rb", "line": 2, "side": "RIGHT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "matches a path holding regex characters as plain text"
rm -rf "$LINES_DIR"

"$DRAFT" 2>&1 | grep -q -- '--check-lines <draft.json> <owner/repo> <pr-number>'
assert_equals "0" "$?" "documents the line check in its own usage"

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
cat > "$LINES_DIR/gh" <<'SH'
#!/usr/bin/env bash
cat <<'DIFF'
diff --git a/app/models/quote.rb b/app/models/quote.rb
--- a/app/models/quote.rb
+++ b/app/models/quote.rb
@@ -40,3 +40,4 @@ class Quote
   def convert
+    order.save
   end
diff --git a/app/other.rb b/app/other.rb
--- a/app/other.rb
+++ b/app/other.rb
@@ -1,2 +1,3 @@
 class Other
+  def run; end
 end
DIFF
SH
chmod +x "$LINES_DIR/gh"
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/models/quote.rb", "line": 42, "side": "LEFT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "1" "$?" "fails a comment on a line no hunk touches in a diff of several files"
rm -rf "$LINES_DIR"

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
cat > "$LINES_DIR/gh" <<'SH'
#!/usr/bin/env bash
cat <<'DIFF'
diff --git a/app/models/quote.rb b/app/models/quote.rb
--- a/app/models/quote.rb
+++ b/app/models/quote.rb
@@ -40,3 +40,4 @@ class Quote
   def convert
+    order.save
   end
diff --git a/app/gone.rb b/app/gone.rb
deleted file mode 100644
--- a/app/gone.rb
+++ /dev/null
@@ -1,2 +0,0 @@
-class Gone
-end
DIFF
SH
chmod +x "$LINES_DIR/gh"
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/gone.rb", "line": 1, "side": "LEFT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "passes a comment on a line a deleted file removes"
rm -rf "$LINES_DIR"

new_diff
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/models/quote.rb", "line": 41, "side": "right", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "reads a side however it is spelled"
drop_diff

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
cat > "$LINES_DIR/gh" <<'SH'
#!/usr/bin/env bash
cat <<'DIFF'
diff --git a/db/quote.sql b/db/quote.sql
--- a/db/quote.sql
+++ b/db/quote.sql
@@ -1,3 +1,3 @@
 select 1
--- the old comment
+-- the new comment
 from quotes
DIFF
SH
chmod +x "$LINES_DIR/gh"
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "db/quote.sql", "line": 2, "side": "RIGHT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "reads a changed line whose own text begins with dashes"
rm -rf "$LINES_DIR"

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
printf 'diff --git a/app/my quote.rb b/app/my quote.rb\n--- a/app/my quote.rb\t\n+++ b/app/my quote.rb\t\n@@ -1,2 +1,3 @@\n class Quote\n+  def convert; end\n end\n' > "$LINES_DIR/diff.txt"
cat > "$LINES_DIR/gh" <<SH
#!/usr/bin/env bash
cat "$LINES_DIR/diff.txt"
SH
chmod +x "$LINES_DIR/gh"
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/my quote.rb", "line": 2, "side": "RIGHT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "matches a path that carries a trailing tab in the diff"
rm -rf "$LINES_DIR"

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
printf 'diff --git a/app/quote.rb b/app/quote.rb\n--- a/app/quote.rb\n+++ b/app/quote.rb\n@@ -1,4 +1,5 @@\n class Quote\n\n+  def convert; end\n end\n' > "$LINES_DIR/diff.txt"
cat > "$LINES_DIR/gh" <<SH
#!/usr/bin/env bash
cat "$LINES_DIR/diff.txt"
SH
chmod +x "$LINES_DIR/gh"
cat > "$LINES_FILE" <<'JSON'
{ "summary": "One finding.",
  "comments": [ { "path": "app/quote.rb", "line": 3, "side": "RIGHT", "body": "a finding" } ],
  "replies": [] }
JSON
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "counts a bare empty line as a line that did not change"
rm -rf "$LINES_DIR"

LINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review_lines_test.XXXXXX")"
LINES_FILE="$LINES_DIR/review.json"
printf 'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"\n--- "a/caf\\303\\251.txt"\n+++ "b/caf\\303\\251.txt"\n@@ -1,2 +1,3 @@\n one\n+two\n three\n' > "$LINES_DIR/diff.txt"
cat > "$LINES_DIR/gh" <<SH
#!/usr/bin/env bash
cat "$LINES_DIR/diff.txt"
SH
chmod +x "$LINES_DIR/gh"
jq -n '{summary:"One finding.",comments:[{path:"café.txt",line:2,side:"RIGHT",body:"a finding"}],replies:[]}' > "$LINES_FILE"
check_lines >/dev/null 2>&1
assert_equals "0" "$?" "matches a path git wrote in quotes with escapes"
rm -rf "$LINES_DIR"

new_diff
printf '{ "summary": "Nothing to raise." }\n' > "$LINES_FILE"
check_lines >/dev/null 2>&1
assert_equals "70" "$?" "refuses a draft with no comments to check"
drop_diff

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
