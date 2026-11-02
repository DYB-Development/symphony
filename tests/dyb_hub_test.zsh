#!/usr/bin/env zsh
# Tests for bin/dyb-hub.sh.
#
# Usage: zsh tests/dyb_hub_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCRIPT="$SCRIPT_DIR/../bin/dyb-hub.sh"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dyb_hub_test.XXXXXX")"
CONNECTION="$WORK/dyb_web"
STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"
printf 'url=https://dyb.example\ntoken=secret\n' > "$CONNECTION"

# A curl that never leaves the machine: it prints the body and status the test sets.
cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do [ "$arg" = "@-" ] && cat > "$STUB_SENT"; done
printf '%s\n' "$@" > "$STUB_SENT.args"
printf '%s\n%s' "$STUB_BODY" "$STUB_STATUS"
STUB
chmod +x "$STUB_BIN/curl"

hub() {
  PATH="$STUB_BIN:$PATH" STUB_SENT="$WORK/sent" SYMPHONY_DYB_WEB_FILE="$CONNECTION" "$SCRIPT" "$@"
}

echo "dyb-hub.sh:"

assert_equals '{"repos":["acme/shop"]}' \
  "$(STUB_BODY='{"answer": {"repos": ["acme/shop"]}}' STUB_STATUS=200 hub get task_choices 2>&1)" \
  "prints the answer of a hub method"

printf '{}' | STUB_BODY='{"error": "The hub holds no pipeline with id 9."}' STUB_STATUS=422 hub post add_work_item >"$WORK/out" 2>&1
exit_status=$?
assert_equals $'The hub holds no pipeline with id 9.\n1' "$(cat "$WORK/out")"$'\n'"$exit_status" \
  "prints the hub's own message for a refusal and fails"

printf '{"title": "Convert quotes"}' | STUB_BODY='{"answer": 12}' STUB_STATUS=200 hub post add_plan >/dev/null 2>&1
assert_equals '{"title": "Convert quotes"}' "$(cat "$WORK/sent" 2>&1)" "sends the params it reads for a post as the request body"

STUB_BODY='{"answer": {"title": "Export quotes"}}' STUB_STATUS=200 hub get work_item work_item_id=12 >/dev/null 2>&1
assert_equals "work_item_id=12" "$(grep -A1 -x -- --data-urlencode "$WORK/sent.args" | tail -1)" "sends the values it is given for a get as the query"

assert_equals "https://dyb.example/console/pipelines/plans/12" "$(hub page /console/pipelines/plans/12 2>&1)" \
  "prints the production address of a page"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
