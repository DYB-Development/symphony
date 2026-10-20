#!/usr/bin/env zsh
# Tests for bin/test-inventory.sh. Each case runs against a stubbed `gh` that
# answers from files written for the case, and a stubbed `claude`.
#
# Usage: zsh tests/test_inventory_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
INVENTORY="$SCRIPT_DIR/../bin/test-inventory.sh"

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
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/test_inventory_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/head" "$WORK/repo"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr diff") cat "$WORK/diff" ;;
  "pr view") printf 'headsha\n' ;;
  "api repos/acme/quotes/contents/"*)
    file=\${2#repos/acme/quotes/contents/}
    cat "$WORK/head/\${file%%\\?*}" 2>/dev/null || exit 1 ;;
esac
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/bin/claude" <<SH
#!/usr/bin/env bash
cat >> "$WORK/asked"
printf '%s\n' "\${CLAUDE_REPLY:-Title: names a behaviour
Body: tests that behaviour}"
exit "\${CLAUDE_EXIT:-0}"
SH
  chmod +x "$WORK/bin/claude"
  DRAFT_FILE="$WORK/repo/.review-7.json"
  RESULT="$WORK/repo/.review-7.tests.json"
}

drop_case() {
  rm -rf "$WORK"
}

head_file() {
  mkdir -p "$WORK/head/${1:h}"
  cat > "$WORK/head/$1"
}

write_diff() { cat > "$WORK/diff"; }

inventory() {
  PATH="$WORK/bin:$PATH" SYMPHONY_AGENT_MODELS_FILE="$WORK/no-models.json" "$INVENTORY" acme/quotes 7 "$DRAFT_FILE"
}

echo "test-inventory.sh:"

new_case
head_file test/models/quote_test.rb <<'RB'
class QuoteTest < ActiveSupport::TestCase
  test "sums the line items into the total" do
    quote = quotes(:two_items)
    assert_equal 30, quote.total
  end
end
RB
write_diff <<'DIFF'
diff --git a/test/models/quote_test.rb b/test/models/quote_test.rb
--- a/test/models/quote_test.rb
+++ b/test/models/quote_test.rb
@@ -1,2 +1,6 @@
 class QuoteTest < ActiveSupport::TestCase
+  test "sums the line items into the total" do
+    quote = quotes(:two_items)
+    assert_equal 30, quote.total
+  end
 end
DIFF
inventory >/dev/null 2>&1
assert_equals "test/models/quote_test.rb 2 1 sums the line items into the total" \
  "$(jq -r '.tests[] | "\(.path) \(.line) \(.assertions) \(.title)"' "$RESULT" 2>/dev/null)" \
  "lists a test the pull request adds with its file, line, assertion count and title"
drop_case

new_case
head_file test/models/quote_test.rb <<'RB'
class QuoteTest < ActiveSupport::TestCase
  test "starts with no line items" do
    assert_empty Quote.new.line_items
  end

  test "sums the line items into the total" do
    quote = quotes(:two_items)
    assert_equal 30, quote.total
  end
end
RB
write_diff <<'DIFF'
diff --git a/test/models/quote_test.rb b/test/models/quote_test.rb
--- a/test/models/quote_test.rb
+++ b/test/models/quote_test.rb
@@ -6,3 +6,4 @@ class QuoteTest < ActiveSupport::TestCase
   test "sums the line items into the total" do
+    quote = quotes(:two_items)
     assert_equal 30, quote.total
   end
DIFF
inventory >/dev/null 2>&1
assert_equals "sums the line items into the total" "$(jq -r '.tests[].title' "$RESULT" 2>/dev/null)" \
  "lists a test whose body the pull request changes and no untouched test beside it"
drop_case

new_case
head_file src/quote.test.js <<'JS'
describe("quote", () => {
  it("sums the line items into the total", () => {
    expect(total([10, 20])).toBe(30);
  });
});
JS
write_diff <<'DIFF'
diff --git a/src/quote.test.js b/src/quote.test.js
--- a/src/quote.test.js
+++ b/src/quote.test.js
@@ -1,2 +1,5 @@
 describe("quote", () => {
+  it("sums the line items into the total", () => {
+    expect(total([10, 20])).toBe(30);
+  });
 });
DIFF
inventory >/dev/null 2>&1
assert_equals "2 1 sums the line items into the total" \
  "$(jq -r '.tests[] | "\(.line) \(.assertions) \(.title)"' "$RESULT" 2>/dev/null)" \
  "lists a JavaScript test written with it and counts its expect calls"
drop_case

new_case
head_file src/key.test.js <<'JS'
describe("key", () => {
  it("gives the browser the platform's publishable key", () => {
    expect(publicKey()).toBe("pk_test");
  });
});
JS
write_diff <<'DIFF'
diff --git a/src/key.test.js b/src/key.test.js
--- a/src/key.test.js
+++ b/src/key.test.js
@@ -1,2 +1,5 @@
 describe("key", () => {
+  it("gives the browser the platform's publishable key", () => {
+    expect(publicKey()).toBe("pk_test");
+  });
 });
DIFF
inventory >/dev/null 2>&1
assert_equals "gives the browser the platform's publishable key" "$(jq -r '.tests[].title' "$RESULT" 2>/dev/null)" \
  "keeps an apostrophe inside a double-quoted test title"
drop_case

new_case
head_file test/quote_test.rb <<'RB'
class QuoteTest < Minitest::Test
  def test_sums_the_line_items_into_the_total
    assert_equal 30, Quote.new([10, 20]).total
  end
end
RB
write_diff <<'DIFF'
diff --git a/test/quote_test.rb b/test/quote_test.rb
--- a/test/quote_test.rb
+++ b/test/quote_test.rb
@@ -1,2 +1,5 @@
 class QuoteTest < Minitest::Test
+  def test_sums_the_line_items_into_the_total
+    assert_equal 30, Quote.new([10, 20]).total
+  end
 end
DIFF
inventory >/dev/null 2>&1
assert_equals "sums the line items into the total" "$(jq -r '.tests[].title' "$RESULT" 2>/dev/null)" \
  "reads the title of a test written as a test_ method from its name"
drop_case

new_case
head_file "test/my quote_test.rb" <<'RB'
class QuoteTest < Minitest::Test
  test "sums the line items into the total" do
    assert_equal 30, quote.total
  end
end
RB
printf 'diff --git a/test/my quote_test.rb b/test/my quote_test.rb\n--- a/test/my quote_test.rb\t\n+++ b/test/my quote_test.rb\t\n@@ -1,2 +1,5 @@\n class QuoteTest < Minitest::Test\n+  test "sums the line items into the total" do\n+    assert_equal 30, quote.total\n+  end\n end\n' > "$WORK/diff"
inventory >/dev/null 2>&1
assert_equals "test/my quote_test.rb 2" "$(jq -r '.tests[] | "\(.path) \(.line)"' "$RESULT" 2>/dev/null)" \
  "lists a test in a file whose name holds a space"
drop_case

new_case
head_file test/quote_test.rb <<'RB'
class QuoteTest < Minitest::Test
  test "sums the line items into the total" do
    assert_equal 30, quote.total
    assert_equal 2, quote.line_items.size
  end
end
RB
write_diff <<'DIFF'
diff --git a/test/quote_test.rb b/test/quote_test.rb
--- a/test/quote_test.rb
+++ b/test/quote_test.rb
@@ -1,2 +1,6 @@
 class QuoteTest < Minitest::Test
+  test "sums the line items into the total" do
+    assert_equal 30, quote.total
+    assert_equal 2, quote.line_items.size
+  end
 end
DIFF
inventory >/dev/null 2>&1
assert_equals "2 true" "$(jq -r '.tests[] | "\(.assertions) \(.tests_more_than_one_thing)"' "$RESULT" 2>/dev/null)" \
  "marks a test with more than one assertion as testing more than one thing"
drop_case

write_added_test() {
  head_file test/quote_test.rb <<'RB'
class QuoteTest < Minitest::Test
  test "works" do
    assert_equal 30, quote.total
  end
end
RB
  write_diff <<'DIFF'
diff --git a/test/quote_test.rb b/test/quote_test.rb
--- a/test/quote_test.rb
+++ b/test/quote_test.rb
@@ -1,2 +1,5 @@
 class QuoteTest < Minitest::Test
+  test "works" do
+    assert_equal 30, quote.total
+  end
 end
DIFF
}

new_case
write_added_test
CLAUDE_REPLY='Title: does not name a behaviour
Body: tests that behaviour' inventory >/dev/null 2>&1
assert_equals "false true" \
  "$(jq -r '.tests[] | "\(.title_names_a_behaviour) \(.body_tests_that_behaviour)"' "$RESULT" 2>/dev/null)" \
  "records whether a model finds the title names a behaviour and the body tests it"
drop_case

new_case
write_added_test
inventory >/dev/null 2>&1
assert_equals "yes yes no" \
  "$(grep -q '^works$' "$WORK/asked" && echo yes || echo no) $(grep -q 'assert_equal 30, quote.total' "$WORK/asked" && echo yes || echo no) $(grep -q 'class QuoteTest' "$WORK/asked" && echo yes || echo no)" \
  "gives the model the test's title and body and nothing else from its file"
drop_case

new_case
write_added_test
CLAUDE_REPLY="The test looks fine." inventory >/dev/null 2>&1
assert_equals "70" "$?" "fails when the model's reply holds no title or body line"
drop_case

new_case
write_added_test
CLAUDE_REPLY='Title: names a behaviour
Body: does not test that behaviour

The body asserts on the total, but the title promises nothing about it.' inventory >/dev/null 2>&1
assert_equals "true false" \
  "$(jq -r '.tests[] | "\(.title_names_a_behaviour) \(.body_tests_that_behaviour)"' "$RESULT" 2>/dev/null)" \
  "reads the title and body lines from a reply that explains itself after them"
drop_case

new_case
write_added_test
rm "$WORK/head/test/quote_test.rb"
assert_equals "70 yes" \
  "$(inventory >/dev/null 2>"$WORK/err"; echo "$? $(grep -q 'test/quote_test.rb.*unread' "$WORK/err" && echo yes || echo no)")" \
  "stops and reports a test file it cannot read as unread rather than as holding no tests"
drop_case

new_case
write_added_test
printf '{ "tests": [ { "path": "test/quote_test.rb", "line": 2, "title": "an old test", "assertions": 1 } ], "hits": [] }\n' > "$RESULT"
CLAUDE_REPLY="The test looks fine." inventory >/dev/null 2>&1
assert_equals "no result" "$([[ -e "$RESULT" ]] && echo "result left" || echo "no result")" \
  "leaves no earlier test list behind when its judgement does not finish"
drop_case

new_case
write_added_test
assert_equals "70 yes" \
  "$(CLAUDE_EXIT=1 inventory >/dev/null 2>"$WORK/err"; echo "$? $(grep -q 'test-inventory' "$WORK/err" && echo yes || echo no)")" \
  "stops and names the test question when its model run fails"
drop_case

new_case
write_added_test
CLAUDE_REPLY='Title: does not name a behaviour
Body: tests that behaviour' inventory >/dev/null 2>&1
assert_equals "test/quote_test.rb 2 test-title-names-no-behaviour Tests tests" \
  "$(jq -r '.hits[] | "\(.path) \(.line) \(.pattern) \(.check) \(.source)"' "$RESULT" 2>/dev/null)" \
  "turns a test whose title names no behaviour into a Tests finding naming what it failed"
drop_case

new_case
write_added_test
CLAUDE_REPLY='Title: names a behaviour
Body: does not test that behaviour' inventory >/dev/null 2>&1
assert_equals "test-body-misses-its-title" "$(jq -r '.hits[].pattern' "$RESULT" 2>/dev/null)" \
  "turns a test whose body does not test its title into a Tests finding"
drop_case

new_case
head_file test/quote_test.rb <<'RB'
class QuoteTest < Minitest::Test
  test "sums the line items into the total" do
    assert_equal 30, quote.total
    assert_equal 2, quote.line_items.size
  end
end
RB
write_diff <<'DIFF'
diff --git a/test/quote_test.rb b/test/quote_test.rb
--- a/test/quote_test.rb
+++ b/test/quote_test.rb
@@ -1,2 +1,6 @@
 class QuoteTest < Minitest::Test
+  test "sums the line items into the total" do
+    assert_equal 30, quote.total
+    assert_equal 2, quote.line_items.size
+  end
 end
DIFF
inventory >/dev/null 2>&1
assert_equals "test-asserts-more-than-one-thing" "$(jq -r '.hits[].pattern' "$RESULT" 2>/dev/null)" \
  "turns a test with more than one assertion into a Tests finding"
drop_case

echo ""
echo "test-inventory.sh --titles:"

TITLES_REPO="$(mktemp -d "${TMPDIR:-/tmp}/test_inventory_titles.XXXXXX")"
git -C "$TITLES_REPO" init -q --template=
git -C "$TITLES_REPO" config user.email test@example.com
git -C "$TITLES_REPO" config user.name Test
mkdir -p "$TITLES_REPO/test/models" "$TITLES_REPO/app/models"
cat > "$TITLES_REPO/test/models/quote_test.rb" <<'RB'
class QuoteTest < ActiveSupport::TestCase
  test "sums the line items into the total" do
    assert_equal 30, quote.total
  end

  test "starts with no line items" do
    assert_empty Quote.new.line_items
  end
end
RB
printf 'class Quote\n  test "not a test file"\nend\n' > "$TITLES_REPO/app/models/quote.rb"
git -C "$TITLES_REPO" add -A
git -C "$TITLES_REPO" commit -q -m first
assert_equals "starts with no line items
sums the line items into the total" \
  "$( (cd "$TITLES_REPO" && "$INVENTORY" --titles HEAD) 2>&1 | sort)" \
  "lists every test title in the repo's test files at a commit"
rm -rf "$TITLES_REPO"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
