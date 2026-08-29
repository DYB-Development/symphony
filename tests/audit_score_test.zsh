#!/usr/bin/env zsh
# Tests for claude/bin/audit-score.sh. Every case runs against audit files and a
# rubric written into a throwaway directory, and nothing here touches the network.
#
# Usage: zsh zsh/audit_score_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCORE="$SCRIPT_DIR/../bin/audit-score.sh"

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

new_dir() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/audit_score_test.XXXXXX")"
  cat > "$WORK/rubric.json" <<'JSON'
{
  "version": 1,
  "cost": {
    "small":    { "weight": 1,  "means": "…" },
    "moderate": { "weight": 3,  "means": "…" },
    "large":    { "weight": 8,  "means": "…" },
    "severe":   { "weight": 20, "means": "…" }
  },
  "horizon": {
    "now":       { "multiplier": 1.0, "means": "…" },
    "at-growth": { "multiplier": 0.6, "means": "…" },
    "at-scale":  { "multiplier": 0.3, "means": "…" }
  }
}
JSON
  export AUDIT_RUBRIC_FILE="$WORK/rubric.json"
}

drop_dir() {
  rm -rf "$WORK"
  unset WORK AUDIT_RUBRIC_FILE
}

echo "audit-score.sh one file:"

new_dir
cat > "$WORK/a.json" <<'JSON'
{
  "rubricVersion": 1,
  "checks": [
    { "check": "Security", "state": "findings", "findings": [
      { "area": "quoting", "cost": "moderate", "horizon": "now" }
    ] }
  ]
}
JSON
assert_equals "quoting  3.0  1" \
  "$("$SCORE" "$WORK/a.json" | sed -n 2p)" \
  "scores an area from the cost and horizon of its findings"
drop_dir

new_dir
cat > "$WORK/a.json" <<'JSON'
{
  "rubricVersion": 1,
  "checks": [
    { "check": "Security", "state": "findings", "findings": [
      { "area": "billing", "cost": "small", "horizon": "at-scale" },
      { "area": "quoting", "cost": "severe", "horizon": "now" }
    ] }
  ]
}
JSON
assert_equals "quoting  20.0  1
billing  0.3  1" \
  "$("$SCORE" "$WORK/a.json" | sed -n '2,3p')" \
  "puts the area that costs more above the one that costs less"
drop_dir

echo ""
echo "audit-score.sh two files:"

new_dir
cat > "$WORK/before.json" <<'JSON'
{
  "rubricVersion": 1,
  "checks": [
    { "check": "Security", "state": "findings", "findings": [
      { "area": "quoting", "cost": "large", "horizon": "now" },
      { "area": "billing", "cost": "moderate", "horizon": "now" }
    ] }
  ]
}
JSON
cat > "$WORK/after.json" <<'JSON'
{
  "rubricVersion": 1,
  "checks": [
    { "check": "Security", "state": "findings", "findings": [
      { "area": "quoting", "cost": "small", "horizon": "now" },
      { "area": "billing", "cost": "large", "horizon": "now" },
      { "area": "deploys", "cost": "moderate", "horizon": "now" }
    ] }
  ]
}
JSON
assert_equals "billing  3.0 → 8.0  +5.0
deploys  0.0 → 3.0  +3.0
quoting  8.0 → 1.0  -7.0" \
  "$("$SCORE" "$WORK/before.json" "$WORK/after.json" | sed -n '2,4p')" \
  "prints what each area moved by between two audits"
drop_dir

echo ""
echo "audit-score.sh refusals:"

new_dir
printf '{ "rubricVersion": 1, "checks": [] }\n' > "$WORK/v1.json"
printf '{ "rubricVersion": 2, "checks": [] }\n' > "$WORK/v2.json"
"$SCORE" "$WORK/v1.json" "$WORK/v2.json" >/dev/null 2>&1
assert_equals "65" "$?" \
  "refuses to compare two audits scored under different rubric versions"
drop_dir

new_dir
cat > "$WORK/scored.json" <<'JSON'
{
  "rubricVersion": 1,
  "checks": [
    { "check": "Security", "state": "findings", "findings": [
      { "area": "quoting", "cost": "small", "horizon": "now", "score": 1.0 }
    ] }
  ]
}
JSON
"$SCORE" "$WORK/scored.json" >/dev/null 2>&1
assert_equals "65" "$?" \
  "refuses an audit file that already carries a score"
drop_dir

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
