#!/usr/bin/env zsh
# Tests for bin/plan-link.sh. Every case runs against a stub gh that writes down
# its calls, so nothing reaches GitHub.
#
# Usage: zsh tests/plan_link_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
LINK="$SCRIPT_DIR/../bin/plan-link.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

# A gh that writes down every call. Issue 12 exists with id 9012, and the plan's
# sub-issues are the numbers in $1.
stub_gh() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/plan_link_test.XXXXXX")"
  GH_LOG="$STUB_BIN/calls"
  : > "$GH_LOG"
  cat > "$STUB_BIN/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
case "\$*" in
  "api repos/acme/widget/issues/12 --jq .id") printf '9012\n' ;;
  "api repos/acme/widget/issues/7/sub_issues --paginate --jq .[].number") printf '%s' "${1:-}" ;;
  "api repos/acme/widget/issues/"*" --jq .id") echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
STUB
  chmod +x "$STUB_BIN/gh"
  path=("$STUB_BIN" $path)
}

drop_stub() {
  path=(${path:#$STUB_BIN})
  rm -rf "$STUB_BIN"
}

echo "plan-link.sh:"

stub_gh
"$LINK" acme/widget 7 12 >/dev/null 2>&1
assert_contains "api -X POST repos/acme/widget/issues/7/sub_issues -F sub_issue_id=9012" "$(cat "$GH_LOG")" \
  "lists the task issue under the plan as a sub-issue"
drop_stub

stub_gh $'3\n12\n'
"$LINK" acme/widget 7 12 >/dev/null 2>&1
code=$?
assert_contains "0 0" "$code $(grep -c -- '-X POST' "$GH_LOG")" \
  "succeeds without adding a task issue already listed under the plan"
drop_stub

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
