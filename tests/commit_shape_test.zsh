#!/usr/bin/env zsh
# Tests for bin/commit-shape.sh. Each case runs against a stubbed `gh` that
# answers from files written for the case, and a stubbed `claude`.
#
# Usage: zsh tests/commit_shape_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SHAPE="$SCRIPT_DIR/../bin/commit-shape.sh"

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
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/commit_shape_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/commits" "$WORK/repo"
  : > "$WORK/commits/order"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
case "\$2" in
  repos/acme/quotes/pulls/7/commits) cat "$WORK/commits/order" ;;
  repos/acme/quotes/commits/*)
    sha=\${2#repos/acme/quotes/commits/}
    case "\$*" in
      *.files*) cat "$WORK/commits/\$sha.files" ;;
      *.commit.message*) cat "$WORK/commits/\$sha.message" ;;
      *diff*) cat "$WORK/commits/\$sha.diff" ;;
    esac ;;
esac
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/bin/claude" <<SH
#!/usr/bin/env bash
cat > "$WORK/asked"
printf '%s\n' "\${CLAUDE_REPLY:-Exception: neither}"
exit "\${CLAUDE_EXIT:-0}"
SH
  chmod +x "$WORK/bin/claude"
  DRAFT_FILE="$WORK/repo/.review-7.json"
  RESULT="$WORK/repo/.review-7.commits.json"
}

drop_case() {
  rm -rf "$WORK"
}

add_commit() {
  local sha="$1" message="$2"
  shift 2
  printf '%s %s\n' "$sha" "${PARENTS:-1}" >> "$WORK/commits/order"
  printf '%s\n' "$message" > "$WORK/commits/$sha.message"
  printf '%s\n' "$@" > "$WORK/commits/$sha.files"
  printf 'diff --git a/%s b/%s\n+changed\n' "${1:-}" "${1:-}" > "$WORK/commits/$sha.diff"
}

shape() {
  PATH="$WORK/bin:$PATH" SYMPHONY_AGENT_MODELS_FILE="$WORK/no-models.json" "$SHAPE" acme/quotes 7 "$DRAFT_FILE"
}

echo "commit-shape.sh:"

new_case
add_commit c1 "Add the quote total" app/models/quote.rb
shape >/dev/null 2>&1
assert_equals "c1 flagged" "$(jq -r '.commits[] | "\(.sha) \(.shape)"' "$RESULT" 2>/dev/null)" \
  "flags a commit that holds code and no test, in a file beside the review draft"
drop_case

new_case
add_commit c1 "Add the quote total" test/models/quote_test.rb app/models/quote.rb
shape >/dev/null 2>&1
assert_equals "c1 test-and-code" "$(jq -r '.commits[] | "\(.sha) \(.shape)"' "$RESULT" 2>/dev/null)" \
  "does not flag a commit that holds a test file and a code file"
drop_case

new_case
add_commit c1 "Cover the quote total" test/models/quote_test.rb test/fixtures/quotes.yml
shape >/dev/null 2>&1
assert_equals "c1 test-only no" \
  "$(jq -r '.commits[] | "\(.sha) \(.shape)"' "$RESULT" 2>/dev/null) $([[ -e "$WORK/asked" ]] && echo asked || echo no)" \
  "treats a commit that changes only test files as holding a test without asking a model"
drop_case

new_case
PARENTS=2 add_commit c1 "Merge branch 'main' into feature" app/models/quote.rb
add_commit c2 "Add the quote total" test/models/quote_test.rb app/models/quote.rb
shape >/dev/null 2>&1
assert_equals "c2" "$(jq -r '.commits[].sha' "$RESULT" 2>/dev/null)" \
  "leaves a merge commit out of the commits it reads"
drop_case

new_case
add_commit c1 "Start the quote total"
shape >/dev/null 2>&1
assert_equals "c1 empty no" \
  "$(jq -r '.commits[] | "\(.sha) \(.shape)"' "$RESULT" 2>/dev/null) $([[ -e "$WORK/asked" ]] && echo asked || echo no)" \
  "flags no commit that changes no code file, so a flagged commit always names its code files"
drop_case

new_case
add_commit c1 "Describe the quote total" README.md docs/quotes.md
shape >/dev/null 2>&1
assert_equals "c1 docs-only no" \
  "$(jq -r '.commits[] | "\(.sha) \(.shape)"' "$RESULT" 2>/dev/null) $([[ -e "$WORK/asked" ]] && echo asked || echo no)" \
  "recognises a commit that changes only documentation without asking a model"
drop_case

new_case
add_commit c1 "Move the total into its own method" app/models/quote.rb
CLAUDE_REPLY="Exception: refactor" shape >/dev/null 2>&1
assert_equals "c1 refactor" "$(jq -r '.commits[] | "\(.sha) \(.exception)"' "$RESULT" 2>/dev/null)" \
  "records the exception a model finds a flagged commit to be"
drop_case

new_case
add_commit c1 "Add the quote total test" test/models/quote_test.rb app/models/quote.rb
add_commit c2 "Move the total into its own method" app/models/quote.rb
shape >/dev/null 2>&1
assert_equals "yes yes no" \
  "$(grep -q 'Move the total into its own method' "$WORK/asked" && echo yes || echo no) $(grep -q '^diff --git' "$WORK/asked" && echo yes || echo no) $(grep -q 'Add the quote total test' "$WORK/asked" && echo yes || echo no)" \
  "gives the model the flagged commit's message and diff and nothing from another commit"
drop_case

new_case
add_commit c1 "Move the total into its own method" app/models/quote.rb
CLAUDE_REPLY="It looks like a refactor to me." shape >/dev/null 2>&1
assert_equals "70" "$?" "fails when the model's reply does not end in an exception line"
drop_case

new_case
add_commit c1 "Move the total into its own method" app/models/quote.rb
assert_equals "70 yes" \
  "$(CLAUDE_EXIT=1 shape >/dev/null 2>"$WORK/err"; echo "$? $(grep -q 'commit-shape' "$WORK/err" && echo yes || echo no)")" \
  "stops and names the commit question when its model run fails"
drop_case

new_case
add_commit c1 "Move the total into its own method" app/models/quote.rb
printf '{ "commits": [] }\n' > "$RESULT"
CLAUDE_EXIT=1 shape >/dev/null 2>&1
assert_equals "no result" "$([[ -e "$RESULT" ]] && echo "result left" || echo "no result")" \
  "leaves no earlier commit result behind when a commit question fails"
drop_case

echo ""
echo "commit-shape.sh --render:"

new_case
add_commit c1aaaaaaaa "Add the quote total" app/models/quote.rb
shape >/dev/null 2>&1
assert_equals '- ❌ **Commits** — one commit changes code with no test.
  - `c1aaaaa` Add the quote total — It changes code in app/models/quote.rb and holds no test. Add the test that drives this change.' \
  "$("$SHAPE" --render "$RESULT" 2>&1)" \
  "renders a flagged commit that is no exception as a Commits finding naming the commit and what it holds"
drop_case

new_case
add_commit c1aaaaaaaa "Move the total into its own method" app/models/quote.rb
CLAUDE_REPLY="Exception: refactor" shape >/dev/null 2>&1
assert_equals '- ✅ **Commits** — nothing found
  - `c1aaaaa` Move the total into its own method — It holds no test and was found to be a refactor that changes no behaviour.' \
  "$("$SHAPE" --render "$RESULT" 2>&1)" \
  "lists a flagged commit found to be an exception with the exception it was found to be"
drop_case

new_case
jq -n '{ commits: [
  { sha: "c1aaaaaaaa", subject: "Add the quote total", code_files: ["app/models/quote.rb"], shape: "flagged", exception: "neither" },
  { sha: "c2aaaaaaaa", subject: "Add the tax total", code_files: ["app/models/tax.rb"], shape: "flagged", exception: "neither" },
  { sha: "c3aaaaaaaa", subject: "Move the total into its own method", code_files: ["app/models/quote.rb"], shape: "flagged", exception: "refactor" } ] }' > "$RESULT"
assert_equals '- ❌ **Commits** — 2 commits change code with no test, and one more was found to be an exception.' \
  "$("$SHAPE" --render "$RESULT" 2>&1 | head -1)" \
  "counts every commit it lists under a Commits finding in the headline"
drop_case

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
