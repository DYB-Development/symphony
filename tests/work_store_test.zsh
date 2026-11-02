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

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
