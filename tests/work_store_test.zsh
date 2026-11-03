#!/usr/bin/env zsh
# Tests for bin/work-store.sh.
#
# Usage: zsh tests/work_store_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCRIPT="$SCRIPT_DIR/../bin/work-store.sh"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/work_store_test.XXXXXX")"
SETTINGS="$WORK/settings"
REPO="$WORK/shop"
mkdir -p "$SETTINGS"
git init -q "$REPO"

store() {
  (cd "$REPO" && SYMPHONY_WORK_DIR="$SETTINGS" "$SCRIPT" "$@")
}

echo "work-store.sh show:"

assert_equals "github" "$(store show 2>&1)" "reports a repo with no setting as using GitHub"

printf '{"store": "dyb_web", "repo": "acme/shop", "pipeline_id": 3, "own_project_id": 7}' > "$SETTINGS/shop.json"
assert_equals $'dyb_web\nrepo=acme/shop\npipeline_id=3\nown_project_id=7' "$(store show 2>&1)" \
  "reports a repo set to dyb_web with the repo, pipeline and link its setting names"

printf '{"store": "jira"}' > "$SETTINGS/shop.json"
assert_equals "work-store.sh: $SETTINGS/shop.json names store \"jira\", which is neither github nor dyb_web" \
  "$(store show 2>&1)" "refuses a setting that names neither GitHub nor dyb_web with the value it held"

echo ""
echo "work-store.sh check:"

STUB_BIN="$WORK/bin"
CONNECTION="$WORK/dyb_web"
mkdir -p "$STUB_BIN"
printf 'url=https://dyb.example\ntoken=secret\n' > "$CONNECTION"

# A curl that never leaves the machine: it answers task_choices with the body the test sets.
cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do [ "$arg" = "@-" ] && cat > "$STUB_SENT"; done
[ -n "${STUB_CALLS:-}" ] && echo "${@: -1}" >> "$STUB_CALLS"
case "${@: -1}" in
  */take_work_item | */take_next_work_item) printf '%s\n%s' "${STUB_CLAIM_BODY:-}" "${STUB_CLAIM_STATUS:-200}" ;;
  *) printf '%s\n%s' "$STUB_BODY" "${STUB_STATUS:-200}" ;;
esac
STUB
chmod +x "$STUB_BIN/curl"

check() {
  (cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_BODY="$1" "$SCRIPT" check)
}

printf '{"store": "dyb_web", "repo": "acme/shop", "pipeline_id": 3, "own_project_id": 7}' > "$SETTINGS/shop.json"
assert_equals "production answers" \
  "$(check '{"answer": {"pipelines": [{"id": 3, "name": "Test-first change"}], "repos": ["acme/shop"], "jobs": [], "products": [], "own_projects": [{"id": 7, "name": "Shop"}], "tasks": []}}' 2>&1)" \
  "reports that production answers when the connection's URL and token are right"

assert_equals $'production answers\nproduction holds no published pipeline with id 3' \
  "$(check '{"answer": {"pipelines": [], "repos": ["acme/shop"], "jobs": [], "products": [], "own_projects": [{"id": 7, "name": "Shop"}], "tasks": []}}' 2>&1)" \
  "names the pipeline production does not hold"

assert_equals $'production answers\nproduction holds no repo named acme/shop' \
  "$(check '{"answer": {"pipelines": [{"id": 3, "name": "Test-first change"}], "repos": [], "jobs": [], "products": [], "own_projects": [{"id": 7, "name": "Shop"}], "tasks": []}}' 2>&1)" \
  "names the repo production does not hold"

assert_equals $'production answers\nproduction holds no own project with id 7' \
  "$(check '{"answer": {"pipelines": [{"id": 3, "name": "Test-first change"}], "repos": ["acme/shop"], "jobs": [{"id": 7, "name": "Shop"}], "products": [], "own_projects": [], "tasks": []}}' 2>&1)" \
  "names the link production does not hold"

echo ""
echo "work-store.sh file-plan:"

file_plan() {
  (cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_BODY="$1" "$SCRIPT" file-plan "Quote-to-order conversion" "$SCRIPT_DIR/fixtures/plan-body.md")
}

file_plan '{"answer": 12}' >/dev/null 2>&1
assert_equals '{"title":"Quote-to-order conversion","priority":"medium","own_project_id":7,"rule":"A quote is a source and the order is the product."}' \
  "$(jq -c '{title, priority, own_project_id, rule}' "$WORK/sent" 2>&1)" \
  "sends a dyb_web repo's plan to production as a draft linked as its setting names"

assert_equals "https://dyb.example/console/pipelines/plans/12" "$(file_plan '{"answer": 12}' 2>&1)" "prints the address of the plan's production page"

assert_equals "The plan has no Risks section" \
  "$(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_STATUS=422 STUB_BODY='{"error": "The plan has no Risks section"}' \
     "$SCRIPT" file-plan "Quote-to-order conversion" "$SCRIPT_DIR/fixtures/plan-body.md" 2>&1)" \
  "reports a plan the hub refuses with the hub's message"

rm -f "$WORK/sent"
sed '/^## 07 What we trade/,/^## 08 Settle first/{/^## 08/!d;}' "$SCRIPT_DIR/fixtures/plan-body.md" > "$WORK/no-trades.md"
(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_BODY='{"answer": 12}' \
  "$SCRIPT" file-plan "Quote-to-order conversion" "$WORK/no-trades.md" >/dev/null 2>&1)
assert_equals "nothing sent" "$([ -e "$WORK/sent" ] && echo sent || echo nothing sent)" "sends nothing to production when the plan body is refused"

echo ""
echo "work-store.sh file-item:"

file_item() {
  (cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_BODY='{"answer": 21}' \
    "$SCRIPT" file-item "Export quotes" "$SCRIPT_DIR/fixtures/task-body.md" "$@")
}

file_item >/dev/null 2>&1
assert_equals $'A rep downloads a CSV of their quotes.\nThe CSV holds each quote\'s total.' "$(jq -r .acceptance_criteria "$WORK/sent" 2>&1)" \
  "sends the task's acceptance criteria to production one to a line"

echo ""
echo "work-store.sh take:"

take() {
  (cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" \
    STUB_CLAIM_BODY='{"answer": 12}' STUB_BODY='{"answer": {"title": "Export quotes", "branch": "12-export-quotes"}}' "$SCRIPT" take 12)
}

rm -f "$WORK/calls"
STUB_CALLS="$WORK/calls" take >/dev/null 2>&1
assert_equals "https://dyb.example/api/v1/hubs/pipelines/take_work_item" "$(head -1 "$WORK/calls" 2>&1)" \
  "takes the named work item by hand, which starts no pipeline run"

take >/dev/null 2>&1
assert_equals "{\"work_item_id\":12,\"session\":\"$(whoami)@$(hostname -s)\"}" "$(jq -c . "$WORK/sent" 2>&1)" \
  "claims the named work item for this machine's session"

assert_equals '{"title":"Export quotes","branch":"12-export-quotes"}' "$(take 2>&1)" "prints the claimed work item as production reads it"

assert_equals "Export quotes waits on Import quotes." \
  "$(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_CLAIM_STATUS=422 \
     STUB_CLAIM_BODY='{"error": "Export quotes waits on Import quotes."}' STUB_BODY='{"answer": {"title": "Export quotes"}}' "$SCRIPT" take 12 2>&1)" \
  "reports a work item that waits on open work with the names of what it waits on"

echo ""
echo "work-store.sh item:"

assert_equals '{"title":"Export quotes","acceptance_criteria":["A rep can export quotes"],"address":"https://dyb.example/console/pipelines/work_items/12"}' \
  "$(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_DYB_WEB_FILE="$CONNECTION" \
     STUB_BODY='{"answer": {"title": "Export quotes", "acceptance_criteria": ["A rep can export quotes"]}}' "$SCRIPT" item 12 2>&1)" \
  "prints the work item with the address of its page in production"

assert_equals $'No work item 99.\nexit 1' \
  "$(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_STATUS=422 \
     STUB_BODY='{"error": "No work item 99."}' "$SCRIPT" item 99 2>&1; echo "exit $?")" \
  "reports a work item production cannot find with production's message"

echo ""
echo "work-store.sh take-next:"

printf '{"store": "dyb_web", "repo": "acme/shop", "pipeline_id": 3}' > "$SETTINGS/shop.json"
rm -f "$WORK/sent" "$WORK/calls"
(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_CALLS="$WORK/calls" \
  STUB_CLAIM_BODY='{"answer": 12}' STUB_BODY='{"answer": {"title": "Export quotes"}}' "$SCRIPT" take-next >/dev/null 2>&1)
assert_equals "https://dyb.example/api/v1/hubs/pipelines/take_next_work_item" "$(head -1 "$WORK/calls" 2>&1)" \
  "takes the next ready work item by hand, which starts no pipeline run"

assert_equals "{\"session\":\"$(whoami)@$(hostname -s)\",\"repo\":\"acme/shop\"}" "$(jq -c . "$WORK/sent" 2>&1)" \
  "claims the next ready work item for the repo its setting names, for this machine's session"

assert_equals '{"title":"Export quotes","id":12}' \
  "$(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" \
     STUB_CLAIM_BODY='{"answer": 12}' STUB_BODY='{"answer": {"title": "Export quotes"}}' "$SCRIPT" take-next 2>&1)" \
  "prints the claimed work item with its id as production reads it"

assert_equals $'No work is ready to take.\nexit 1' \
  "$(cd "$REPO" && PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" STUB_CLAIM_STATUS=422 \
     STUB_CLAIM_BODY='{"error": "No work is ready to take."}' STUB_BODY='{"answer": {"title": "Export quotes"}}' "$SCRIPT" take-next 2>&1; echo "exit $?")" \
  "reports that no work is ready with production's message"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
