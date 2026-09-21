#!/usr/bin/env zsh
# Tests for the reusable release workflow and the caller every gem copies in.
# A typo in either is silent until a release fails, so the shape is asserted
# here rather than read by eye.
#
# Usage: zsh tests/gem_release_workflow_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
WORKFLOW="$SCRIPT_DIR/../.github/workflows/gem-release.yml"
CALLER="$SCRIPT_DIR/../templates/gem-release-caller.yml"

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

# Reads a workflow with Ruby, which parses `on:` as the boolean true the way
# YAML 1.1 says to, so the triggers are looked up under both spellings.
query() {
  ruby -ryaml -e '
    doc = YAML.load_file(ARGV[0], aliases: true)
    doc["on"] ||= doc[true]
    path = ARGV[1].split(".")
    value = path.reduce(doc) { |node, key| node.is_a?(Array) ? node[key.to_i] : node&.[](key) }
    puts value.is_a?(Hash) ? value.keys.join(",") : Array(value).join(",")
  ' "$2" "$1"
}

echo "gem-release workflow:"

assert_equals "workflow_call" "$(query "on" "$WORKFLOW")" \
  "is called by a gem's own workflow and triggered by nothing else"

assert_contains "id-token" "$(query "jobs.release.permissions" "$WORKFLOW")" \
  "asks for the token rubygems.org exchanges for a publishing credential"

assert_contains "issues" "$(query "jobs.notify.permissions" "$WORKFLOW")" \
  "asks for the access it needs to open the failure issue"

assert_equals "contents,id-token,issues,actions" "$(query "jobs.release.permissions" "$CALLER")" \
  "grants the caller every permission the reusable workflow's jobs ask for"

assert_equals "push,workflow_dispatch" "$(query "on" "$CALLER")" \
  "is run by a merge to main and by hand from the Actions tab"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
