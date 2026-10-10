#!/usr/bin/env zsh
# Tests for bin/plan-progress.sh. Every case runs against a stub gh, so nothing
# reaches GitHub.
#
# Usage: zsh tests/plan_progress_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
READER="$SCRIPT_DIR/../bin/plan-progress.sh"

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

# A gh where task 12 sits under plan 7, "Quote builder", with 3 of 8 units
# closed across four stages, task 13 sits under no plan, and task 14 sits under
# plan 8, whose one unit names another stage above its `Part of` line.
SHARED_STUBS="$(mktemp -d "${TMPDIR:-/tmp}/plan_progress_stubs.XXXXXX")"
cat > "$SHARED_STUBS/gh-1" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "api repos/acme/widget/issues/12/parent --jq "*)
    printf '7\tQuote builder\t3\t8\n' ;;
  "api repos/acme/widget/issues/7/sub_issues --paginate")
    unit() { jq -nc --arg state "$1" --arg stage "$2" '{state: $state, body: ("## Part of\nQuote building, " + $stage + ".\n")}'; }
    {
      unit closed "stage 1 of 4 — End to end"
      unit closed "stage 1 of 4 — End to end"
      unit closed "stage 2 of 4 — Enrich"
      unit open "stage 2 of 4 — Enrich"
      unit open "stage 2 of 4 — Enrich"
      unit open "stage 3 of 4 — Simplify"
      unit open "stage 4 of 4 — Harden"
      unit open "stage 4 of 4 — Harden"
    } | jq -sc . ;;
  "api repos/acme/widget/issues/12 --jq .body")
    printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n\n## How it fits\n\n## Acceptance criteria\n- [x] A rep can quote.\n- [ ] A rep can save.\n- [ ] A rep can send.\n\n## Out of scope\n- [ ] not a criterion\n' ;;
  "api repos/acme/widget/issues/14/parent --jq "*)
    printf '8\tQuote export\t1\t1\n' ;;
  "api repos/acme/widget/issues/14 --jq .body")
    printf '## Part of\nQuote export, stage 3 of 4 — Simplify.\n' ;;
  "api repos/acme/widget/issues/8/sub_issues --paginate")
    jq -nc '[{state: "closed", body: "Follows the work of stage 1 of 4.\n\n## Part of\nQuote export, stage 3 of 4 — Simplify.\n"}]' ;;
  "api repos/acme/widget/issues/16/parent --jq "*)
    printf '9\tQuote archive\t2\t5\n' ;;
  "api repos/acme/widget/issues/16 --jq .body")
    printf '## Part of\nQuote archive, stage 1 of 4 — End to end.\n' ;;
  "api repos/acme/widget/issues/9/sub_issues --paginate")
    echo "error connecting to api.github.com" >&2; exit 1 ;;
  "api repos/acme/widget/issues/17/parent --jq "*)
    printf '9\tQuote plans\t1\t2\tacme/plans\n' ;;
  "api repos/acme/widget/issues/17 --jq .body")
    printf '## Part of\nQuote plans, stage 1 of 4 — End to end.\n' ;;
  "api repos/acme/plans/issues/9/sub_issues --paginate")
    jq -nc '[{state: "closed", body: "## Part of\nQuote plans, stage 1 of 4 — End to end.\n"}, {state: "open", body: "## Part of\nQuote plans, stage 2 of 4 — Enrich.\n"}]' ;;
  "api repos/acme/widget/issues/15/parent --jq "*)
    echo "error connecting to api.github.com" >&2; exit 1 ;;
  "api repos/acme/widget/issues/13/parent --jq "*)
    echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
STUB
chmod +x "$SHARED_STUBS/gh-1"

stub_gh() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/plan_progress_test.XXXXXX")"
  ln -s "$SHARED_STUBS/gh-1" "$STUB_BIN/gh"
  path=("$STUB_BIN" $path)
}

drop_stub() {
  path=(${path:#$STUB_BIN})
  rm -rf "$STUB_BIN"
}

echo "plan-progress.sh:"

stub_gh
assert_equals $'Quote builder\t3\t8\tstage 2 of 4 — Enrich' "$("$READER" acme/widget 12 2>&1 | cut -f1-4)" \
  "prints the plan's title, its closed and total units, and the task's stage"
drop_stub

stub_gh
assert_equals "1:2/2 2:1/3 3:0/1 4:0/2" "$("$READER" acme/widget 12 2>&1 | cut -f5)" \
  "prints each stage's closed units out of its units, in stage order"
drop_stub

stub_gh
assert_equals "3:1/1" "$("$READER" acme/widget 14 2>&1 | cut -f5)" \
  "takes each unit's stage from its Part of line"
drop_stub

stub_gh
assert_equals "1/3" "$("$READER" acme/widget 12 2>&1 | cut -f6)" \
  "prints how many of the task's acceptance criteria are ticked out of all of them"
drop_stub

stub_gh
output=$("$READER" acme/widget 13 2>/dev/null)
code=$?
assert_equals "1 " "$code $output" "prints nothing and fails for a task listed under no plan"
drop_stub

stub_gh
output=$("$READER" acme/widget 15 2>/dev/null)
code=$?
assert_equals "69 " "$code $output" "prints nothing and exits 69 when GitHub cannot be read"
drop_stub

stub_gh
output=$("$READER" acme/widget 16 2>/dev/null)
code=$?
assert_equals "69 " "$code $output" "prints nothing and exits 69 when a later read from GitHub fails"
drop_stub

stub_gh
assert_equals $'Quote plans\t1\t2\tstage 1 of 4 — End to end\t1:1/1 2:0/1' "$("$READER" acme/widget 17 2>&1 | cut -f1-5)" \
  "counts a plan's units from the plan's own repo when the task lives in another"
drop_stub

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
rm -rf "$SHARED_STUBS"
[[ $FAIL -eq 0 ]]
