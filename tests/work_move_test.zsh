#!/usr/bin/env zsh
# Tests for bin/work-move.sh.
#
# Usage: zsh tests/work_move_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCRIPT="$SCRIPT_DIR/../bin/work-move.sh"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/work_move_test.XXXXXX")"
SETTINGS="$WORK/settings"
STUB_BIN="$WORK/bin"
CONNECTION="$WORK/dyb_web"
mkdir -p "$SETTINGS" "$STUB_BIN"
printf 'url=https://dyb.example\ntoken=secret\n' > "$CONNECTION"
printf '{"store": "dyb_web", "repo": "acme/dyb_web", "pipeline_id": 3, "own_project_id": 7}' > "$SETTINGS/dyb_web.json"

# A curl that never leaves the machine: it keeps each body posted, one to a line,
# and answers move_in_plan with a plan id.
cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do [ "$arg" = "@-" ] && { cat >> "$STUB_SENT"; echo >> "$STUB_SENT"; }; done
body='{"answer": {"plan_id": 12, "work_items": {}}}'
printf '%s\n%s' "${STUB_BODY:-$body}" "${STUB_STATUS:-200}"
STUB
chmod +x "$STUB_BIN/curl"

# A gh that never leaves the machine: it answers the plan list and the ticket
# list for acme/dyb_web with the JSON the test sets.
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
[[ " $* " == *" --repo acme/dyb_web "* ]] || { echo "gh stub: unexpected repo in $*" >&2; exit 1; }
if [[ " $* " == *" --label type:plan "* ]]; then printf '%s' "$STUB_PLANS"; else printf '%s' "${STUB_TICKETS:-[]}"; fi
STUB
chmod +x "$STUB_BIN/gh"

PLAN_BODY="$(cat "$SCRIPT_DIR/fixtures/plan-body.md")"

plan() {
  jq -n --argjson number "$1" --arg title "$2" --arg state "$3" --arg body "${4:-$PLAN_BODY}" --argjson labels "${5:-[]}" \
    '{number: $number, title: $title, state: $state, body: $body, labels: ([{name: "type:plan"}] + $labels)}'
}

move() {
  rm -f "$WORK/sent"
  PATH="$STUB_BIN:$PATH" SYMPHONY_WORK_DIR="$SETTINGS" SYMPHONY_DYB_WEB_FILE="$CONNECTION" STUB_SENT="$WORK/sent" \
    STUB_PLANS="$1" STUB_TICKETS="${2:-[]}" "$SCRIPT"
}

sent() { jq -sc "$1" "$WORK/sent" 2>&1; }

echo "work-move.sh:"

move "[$(plan 41 "Quote-to-order conversion" OPEN)]" >/dev/null 2>&1
assert_equals '["Quote-to-order conversion"]' "$(sent 'map(.title)')" "moves an open plan issue into production"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
