#!/usr/bin/env zsh
# Tests for bin/status-line.sh. Every case runs in a throwaway repo with its own
# cache directory, against a stub gh that writes down its calls.
#
# Usage: zsh tests/status_line_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STATUS_LINE="$SCRIPT_DIR/../bin/status-line.sh"

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

# A repo of acme/widget on branch $1, a cache directory, and a gh where task 12
# sits under plan 7, "Quote builder", with 3 of 8 units closed.
new_repo() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/status_line_test.XXXXXX")"
  REPO="$WORK/widget"
  git init -q -b "$1" "$REPO"
  git -C "$REPO" remote add origin git@github.com:acme/widget.git
  export STATUS_LINE_DIR="$WORK/cache"
  GH_LOG="$WORK/calls"
  : > "$GH_LOG"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
case "\$*" in
  "api repos/acme/widget/issues/12/parent --jq "*)
    printf 'Quote builder\t3\t8\n' ;;
  "api repos/acme/widget/issues/12 --jq .body")
    printf '## Part of\nQuote building, stage 2 of 4 — Enrich.\n' ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
STUB
  chmod +x "$WORK/bin/gh"
  path=("$WORK/bin" $path)
}

drop_repo() {
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
  unset STATUS_LINE_DIR
}

status_line() {
  jq -nc --arg dir "$REPO" '{workspace: {current_dir: $dir}}' | "$STATUS_LINE" 2>&1
}

echo "status-line.sh:"

new_repo 12-quote-lines
assert_equals "Quote builder ███░░░░░░░ 3/8 · stage 2 of 4 — Enrich" "$(status_line)" \
  "shows the plan's title, a bar, the closed units out of all units, and the task's stage"
drop_repo

new_repo feature/quote-lines
assert_equals "" "$(status_line)" "shows no plan progress on a branch whose name has no leading issue number"
drop_repo

new_repo 13-loose-task
assert_equals "" "$(status_line)" "shows no plan progress on a branch whose issue is listed under no plan"
drop_repo

new_repo 12-quote-lines
STATUS_LINE_NOW=1000 status_line >/dev/null
STATUS_LINE_NOW=1059 status_line >/dev/null
assert_equals "1" "$(grep -c '/parent' "$GH_LOG")" \
  "asks GitHub once for refreshes within the same minute"
drop_repo

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
