#!/usr/bin/env zsh
# Tests that every agent names its rules file by a path inside this package as
# well as by the linked home path. The home path resolves only once the readme's
# links are in place, so an agent with no second path cannot find its rules on a
# checkout that has not been linked.
#
# Usage: zsh tests/agent_rules_path_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

# The rules file an agent is told to read first, taken from its own prose.
primary_rules_of() {
  grep -om1 '~/\.claude/rules/[a-z-]*\.\(md\|json\)' "$1" | sed 's|.*/||'
}

echo "agents name their rules by a path in this package:"

for agent in "$ROOT"/agents/*.md; do
  name="${agent:t}"
  rules="$(primary_rules_of "$agent")"

  if [[ -z "$rules" ]]; then
    fail "$name names a rules file"
    continue
  fi

  if [[ ! -f "$ROOT/rules/$rules" ]]; then
    fail "$name names a rules file this package contains"
    printf '      names %s, which is not under rules/\n' "$rules"
  elif grep -qF "\`rules/$rules\`" "$agent"; then
    ok "$name also names rules/$rules inside this package"
  else
    fail "$name also names rules/$rules inside this package"
  fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
