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
  mkdir -p "$WORK/bin" "$WORK/packs" "$WORK/repo" "$WORK/head"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr diff") [ ! -e "$WORK/diff.fails" ] || exit 1; cat "$WORK/diff" ;;
  "pr view") printf 'headsha\n' ;;
  "api repos/acme/quotes/contents/"*)
    file=\${2#repos/acme/quotes/contents/}
    file=\${file%%\\?*}
    if [ -e "$WORK/head/\$file.fails" ]; then echo "gh: Server Error (HTTP 500)" >&2; exit 1; fi
    cat "$WORK/head/\$file" 2>/dev/null || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
esac
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/packs/test.json" <<'JSON'
{
  "version": 1,
  "applies": "always",
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
cat > "$WORK/given.diff" <<'DIFF'
diff --git a/app/quote.rb b/app/quote.rb
index 1111111..2222222 100644
--- a/app/quote.rb
+++ b/app/quote.rb
@@ -10,2 +10,3 @@ class Quote
   def total
+    binding.pry
     items.sum(&:price)
DIFF
touch "$WORK/diff.fails"
PATH="$WORK/bin:$PATH" SYMPHONY_PATTERNS_DIR="$WORK/packs" "$SCAN" acme/quotes 7 "$DRAFT_FILE" --diff "$WORK/given.diff" >/dev/null 2>&1
assert_equals "app/quote.rb 11 debug-print" \
  "$(jq -r '.hits[] | "\(.path) \(.line) \(.pattern)"' "$RESULT" 2>/dev/null)" \
  "scans a diff file passed in without fetching the diff from GitHub"
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

new_case
write_diff </dev/null
jq 'del(.patterns[0].fix)' "$WORK/packs/test.json" > "$WORK/packs/broken.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "65" "$?" "refuses a pattern that does not say what to do instead"
drop_case

new_case
write_diff </dev/null
jq 'del(.patterns[0].reason)' "$WORK/packs/test.json" > "$WORK/packs/broken.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "65" "$?" "refuses a pattern that does not say why it is a problem"
drop_case

new_case
write_diff </dev/null
jq 'del(.patterns[0].check)' "$WORK/packs/test.json" > "$WORK/packs/broken.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "65" "$?" "refuses a pattern that does not name its check"
drop_case

new_case
write_diff <<'DIFF'
diff --git a/app/x.rb b/app/x.rb
--- a/app/x.rb
+++ b/app/x.rb
@@ -1,0 +1,1 @@
+binding.pry
DIFF
jq '.patterns[0].regex = "binding(pry"' "$WORK/packs/test.json" > "$WORK/packs/broken.json"
rm "$WORK/packs/test.json"
assert_equals "70 yes" \
  "$(scan >/dev/null 2>"$WORK/err"; echo "$? $(grep -q 'debug-print' "$WORK/err" && echo yes || echo no)")" \
  "stops and names a pattern that is not a valid expression"
drop_case

new_case
write_diff </dev/null
printf '{ "version": 1, "applies": "always", "patterns": [\n' > "$WORK/packs/half.json"
assert_equals "70 yes" \
  "$(scan >/dev/null 2>"$WORK/err"; echo "$? $(grep -q 'pack half' "$WORK/err" && echo yes || echo no)")" \
  "stops and names a pack that cannot be read"
drop_case

new_case
touch "$WORK/diff.fails"
scan >/dev/null 2>&1
assert_equals "70" "$?" "stops when the diff cannot be read rather than reporting no hits"
drop_case

new_case
write_diff </dev/null
touch "$WORK/head/Gemfile.lock.fails"
assert_equals "70 yes" \
  "$(scan >/dev/null 2>"$WORK/err"; echo "$? $(grep -q 'Gemfile.lock' "$WORK/err" && echo yes || echo no)")" \
  "stops and names a lockfile that cannot be read rather than applying fewer packs"
drop_case

new_case
write_diff </dev/null
printf '{ "hits": [], "patterns": [ { "pack": "test", "name": "debug-print", "check": "Patterns" } ] }\n' > "$RESULT"
jq '.patterns[0].regex = "binding(pry"' "$WORK/packs/test.json" > "$WORK/packs/broken.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "no result" "$([[ -e "$RESULT" ]] && echo "result left" || echo "no result")" \
  "leaves no scan result behind when a pattern could not run, so no check reads nothing found from it"
drop_case

new_case
write_diff </dev/null
jq 'del(.applies)' "$WORK/packs/test.json" > "$WORK/packs/broken.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "65" "$?" "refuses a pack that does not say when it applies"
drop_case

new_case
write_diff </dev/null
jq '.applies = { framework: "rails" }' "$WORK/packs/test.json" > "$WORK/packs/rails.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "0" "$?" "accepts a pack that applies when the repo uses a named framework"
drop_case

new_case
write_diff </dev/null
jq '.applies = { library: "devise" }' "$WORK/packs/test.json" > "$WORK/packs/devise.json"
rm "$WORK/packs/test.json"
scan >/dev/null 2>&1
assert_equals "0" "$?" "accepts a pack that applies when the repo depends on a named library"
drop_case

debug_pack_applying_to() {
  jq --argjson applies "$1" '.applies = $applies' "$WORK/packs/test.json" > "$WORK/packs/scoped.json"
  rm "$WORK/packs/test.json"
}

write_pry_diff() {
  printf 'diff --git a/app/x.rb b/app/x.rb\n--- a/app/x.rb\n+++ b/app/x.rb\n@@ -1,0 +1,1 @@\n+binding.pry\n' > "$WORK/diff"
}

new_case
write_pry_diff
debug_pack_applying_to '{"library": "pry"}'
scan >/dev/null 2>&1
assert_equals "0" "$(jq '.hits | length' "$RESULT" 2>/dev/null)" \
  "does not apply a library pack when the repo does not depend on the library"
drop_case

new_case
write_pry_diff
debug_pack_applying_to '{"library": "pry"}'
printf 'GEM\n  remote: https://rubygems.org/\n  specs:\n    pry (0.14.2)\n' > "$WORK/head/Gemfile.lock"
scan >/dev/null 2>&1
assert_equals "1" "$(jq '.hits | length' "$RESULT" 2>/dev/null)" \
  "applies a library pack when the repo's Gemfile.lock at the head commit lists the library"
drop_case

new_case
write_pry_diff
debug_pack_applying_to '{"library": "pry"}'
printf '{\n  "dependencies": {\n    "pry": "^1.0.0"\n  }\n}\n' > "$WORK/head/package.json"
scan >/dev/null 2>&1
assert_equals "1" "$(jq '.hits | length' "$RESULT" 2>/dev/null)" \
  "applies a library pack when the repo's package.json at the head commit depends on the library"
drop_case

new_case
write_pry_diff
debug_pack_applying_to '{"framework": "rails"}'
printf 'GEM\n  specs:\n    rails (7.1.3)\n' > "$WORK/head/Gemfile.lock"
scan >/dev/null 2>&1
assert_equals "1" "$(jq '.hits | length' "$RESULT" 2>/dev/null)" \
  "applies a framework pack when the repo's Gemfile.lock at the head commit lists the framework"
drop_case

new_case
write_pry_diff
debug_pack_applying_to '{"framework": "rails"}'
printf 'GEM\n  specs:\n    rails (7.1.3)\n' > "$WORK/head/Gemfile.lock"
scan >/dev/null 2>&1
assert_equals "scoped Gemfile.lock" \
  "$(jq -r '.applied[] | select(.pack == "scoped") | "\(.pack) \(.shown_by)"' "$RESULT" 2>/dev/null)" \
  "names each pack it applied and the file that showed the pack applies"
drop_case

write_line_diff() {
  printf 'diff --git a/app/x.rb b/app/x.rb\n--- a/app/x.rb\n+++ b/app/x.rb\n@@ -1,0 +1,1 @@\n+%s\n' "$1" > "$WORK/diff"
}

new_case
printf 'diff --git "a/app/my caf\\303\\251.rb" "b/app/my caf\\303\\251.rb"\n--- "a/app/my caf\\303\\251.rb"\n+++ "b/app/my caf\\303\\251.rb"\n@@ -1,0 +1,1 @@\n+binding.pry\n' > "$WORK/diff"
scan >/dev/null 2>&1
assert_equals "app/my café.rb 1" "$(jq -r '.hits[] | "\(.path) \(.line)"' "$RESULT" 2>/dev/null)" \
  "reads the path of a file whose name git wrote in quotes with escapes"
drop_case

new_case
write_line_diff 'binding.pry # symphony-allow: debug-print'
scan >/dev/null 2>&1
assert_equals "0" "$(jq '.hits | length' "$RESULT" 2>/dev/null)" \
  "does not report a line for a pattern its false-hit marker names"
drop_case

new_case
write_line_diff 'binding.pry # symphony-allow: debug-print'
scan >/dev/null 2>&1
assert_equals "app/x.rb 1 debug-print" \
  "$(jq -r '.skipped[] | "\(.path) \(.line) \(.pattern)"' "$RESULT" 2>/dev/null)" \
  "lists every hit it skipped because of a false-hit marker"
drop_case

new_case
write_line_diff 'total = 1 # symphony-allow:'
scan >/dev/null 2>&1
assert_equals "app/x.rb 1 unknown-false-hit-marker Patterns" \
  "$(jq -r '.hits[] | "\(.path) \(.line) \(.pattern) \(.check)"' "$RESULT" 2>/dev/null)" \
  "reports a false-hit marker that names no pattern"
drop_case

new_case
write_line_diff 'total = 1 # symphony-allow: no-such-pattern'
scan >/dev/null 2>&1
assert_equals "app/x.rb 1 unknown-false-hit-marker" \
  "$(jq -r '.hits[] | "\(.path) \(.line) \(.pattern)"' "$RESULT" 2>/dev/null)" \
  "reports a false-hit marker naming a pattern that does not exist"
drop_case

core_checks_for() {
  new_case
  printf 'diff --git a/config/x b/config/x\n--- a/config/x\n+++ b/config/x\n@@ -1,0 +1,1 @@\n+%s\n' "$1" > "$WORK/diff"
  PATH="$WORK/bin:$PATH" "$SCAN" acme/quotes 7 "$DRAFT_FILE" >/dev/null
  jq -r '[.hits[].check] | unique | join(",")' "$RESULT" 2>/dev/null
  drop_case
}

assert_equals "Security" "$(core_checks_for '-----BEGIN RSA PRIVATE KEY-----')" \
  "finds a private key written into an added line with the core pack"

assert_equals "Security" "$(core_checks_for 'DATABASE_URL=postgres://app:Hx7pQ2mZ9w@db.internal:5432/app')" \
  "finds a connection string carrying a password with the core pack"

assert_equals "Security" "$(core_checks_for 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE')" \
  "finds a cloud access key id with the core pack"

assert_equals "Security" "$(core_checks_for 'auth_token: "q3Lm9Pz2Wv8Rt5Ny7Kb"')" \
  "finds a token written into an added line with the core pack"

rails_patterns_for() {
  new_case
  printf 'diff --git a/app/x.rb b/app/x.rb\n--- a/app/x.rb\n+++ b/app/x.rb\n@@ -1,0 +1,1 @@\n+%s\n' "$1" > "$WORK/diff"
  printf 'GEM\n  specs:\n    rails (7.1.3)\n' > "$WORK/head/Gemfile.lock"
  PATH="$WORK/bin:$PATH" "$SCAN" acme/quotes 7 "$DRAFT_FILE" >/dev/null
  jq -r '[.hits[] | select(.pattern | startswith("rails-")) | .pattern] | join(",")' "$RESULT" 2>/dev/null
  drop_case
}

assert_equals "rails-params-in-query" \
  "$(rails_patterns_for 'Quote.where("name = '"'"'#{params[:name]}'"'"'")')" \
  "finds request input written into a database query in a Rails repo"

assert_equals "rails-params-in-command" \
  "$(rails_patterns_for 'system("convert #{params[:file]} out.png")')" \
  "finds request input written into a shell command in a Rails repo"

assert_equals "rails-params-in-path" \
  "$(rails_patterns_for 'send_file(Rails.root.join("exports", params[:name]))')" \
  "finds request input reaching a file path in a Rails repo"

assert_equals "rails-unescaped-output" \
  "$(rails_patterns_for '<%= comment.body.html_safe %>')" \
  "finds HTML output marked safe without escaping in a Rails repo"

assert_equals "rails-query-in-loop" \
  "$(rails_patterns_for 'items.each { |item| Product.find(item.product_id) }')" \
  "finds a query inside a loop in a Rails repo"

assert_equals "rails-unbounded-fetch" \
  "$(rails_patterns_for 'Quote.all.each do |quote|')" \
  "finds a fetch of every row with no limit in a Rails repo"

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
