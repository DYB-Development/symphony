#!/usr/bin/env zsh
# Tests for bin/pattern-scan.sh. Each case runs against a stubbed `gh` that
# prints a fixed diff, and a pack directory written for the case.
#
# Usage: zsh tests/pattern_scan_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCAN="$SCRIPT_DIR/../bin/pattern-scan.sh"

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

new_case() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/pattern_scan_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/packs" "$WORK/repo"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
cat "$WORK/diff"
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/packs/test.json" <<'JSON'
{
  "version": 1,
  "patterns": [
    {
      "name": "debug-print",
      "check": "Patterns",
      "regex": "binding\\.pry",
      "reason": "A debugger call stops the process that reaches it.",
      "fix": "Remove the debugger call.",
      "examples": { "match": "binding.pry", "miss": "binding_pry_helper" }
    }
  ]
}
JSON
  DRAFT_FILE="$WORK/repo/.review-7.json"
  RESULT="$WORK/repo/.review-7.scan.json"
}

drop_case() {
  rm -rf "$WORK"
}

write_diff() { cat > "$WORK/diff"; }

scan() {
  PATH="$WORK/bin:$PATH" SYMPHONY_PATTERNS_DIR="$WORK/packs" "$SCAN" acme/quotes 7 "$DRAFT_FILE"
}

echo "pattern-scan.sh:"

new_case
write_diff <<'DIFF'
diff --git a/app/quote.rb b/app/quote.rb
index 1111111..2222222 100644
--- a/app/quote.rb
+++ b/app/quote.rb
@@ -10,2 +10,3 @@ class Quote
   def total
+    binding.pry
     items.sum(&:price)
DIFF
scan >/dev/null
assert_equals "app/quote.rb 11 debug-print Patterns" \
  "$(jq -r '.hits[] | "\(.path) \(.line) \(.pattern) \(.check)"' "$RESULT" 2>/dev/null)" \
  "lists an added line that matches a pattern with its file, line, pattern and check"
drop_case

new_case
write_diff <<'DIFF'
diff --git a/app/quote.rb b/app/quote.rb
--- a/app/quote.rb
+++ b/app/quote.rb
@@ -1,0 +1,1 @@
+binding.pry
DIFF
scan >/dev/null
assert_equals "A debugger call stops the process that reaches it. | Remove the debugger call." \
  "$(jq -r '.hits[] | "\(.reason) | \(.fix)"' "$RESULT" 2>/dev/null)" \
  "gives each hit the pattern's reason and what to do instead"
drop_case

new_case
write_diff <<'DIFF'
diff --git a/app/quote.rb b/app/quote.rb
--- a/app/quote.rb
+++ b/app/quote.rb
@@ -1,3 +1,3 @@
 binding.pry
-binding.pry
+total
DIFF
scan >/dev/null
assert_equals "0" "$(jq '.hits | length' "$RESULT" 2>/dev/null)" \
  "reports no line the pull request removes or leaves unchanged"
drop_case

new_case
write_diff <<'DIFF'
diff --git a/app/quote.rb b/app/quote.rb
--- a/app/quote.rb
+++ b/app/quote.rb
@@ -1,0 +1,1 @@
+total
DIFF
scan >/dev/null
assert_equals "test debug-print Patterns" \
  "$(jq -r '.patterns[] | "\(.pack) \(.name) \(.check)"' "$RESULT" 2>/dev/null)" \
  "lists every pattern that ran, with its pack, even when it matched nothing"
drop_case

new_case
write_diff <<'DIFF'
diff --git a/app/quote.rb b/app/quote.rb
--- a/app/quote.rb
+++ b/app/quote.rb
@@ -1,0 +1,1 @@
+total
DIFF
mkdir -p "$WORK/elsewhere"
DRAFT_FILE="$WORK/elsewhere/.review-12.json"
scan >/dev/null
assert_equals "$WORK/elsewhere/.review-12.scan.json" "$(ls "$WORK"/elsewhere/.review-12.scan.json 2>/dev/null)" \
  "writes its result beside the review draft, named after it"
drop_case

new_case
write_diff <<'DIFF'
diff --git a/config/payments.rb b/config/payments.rb
--- a/config/payments.rb
+++ b/config/payments.rb
@@ -1,0 +1,1 @@
+STRIPE_API_KEY = "q8Zr2mWx7pLk4vNt9sYbHj3c"
DIFF
PATH="$WORK/bin:$PATH" "$SCAN" acme/quotes 7 "$DRAFT_FILE" >/dev/null
assert_equals "core credential-in-code Security" \
  "$(jq -r '.hits[] as $hit | .patterns[] | select(.name == $hit.pattern) | "\(.pack) \(.name) \(.check)"' "$RESULT" 2>/dev/null)" \
  "finds a credential written into the code with the core pack this package ships"
drop_case

wrong_examples=()
for pack in "$SCRIPT_DIR"/../rules/patterns/*.json; do
  while IFS=$'\037' read -r name regex match miss; do
    printf '%s\n' "$match" | grep -q -E -e "$regex" || wrong_examples+=("$name misses its match example")
    printf '%s\n' "$miss" | grep -q -E -e "$regex" && wrong_examples+=("$name matches its miss example")
  done < <(jq -r '.patterns[] | [.name, .regex, .examples.match, .examples.miss] | join("\u001f")' "$pack")
done
assert_equals "" "${(j:, :)wrong_examples}" \
  "every shipped pattern matches its match example and not its miss example"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
