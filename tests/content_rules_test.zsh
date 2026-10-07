#!/usr/bin/env zsh
# Runs bin/check-content.sh against checks/rules.json, so every wording rule the
# package's instruction files must meet is enforced by this one run.
#
# Usage: zsh tests/content_rules_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"

echo "content rules:"

if output=$("$ROOT/bin/check-content.sh" "$ROOT/checks/rules.json" "$ROOT" 2>&1); then
  printf '  \033[32m✓\033[0m every rule in checks/rules.json holds\n'
  printf '\n1 passed, 0 failed\n'
else
  printf '  \033[31m✗\033[0m every rule in checks/rules.json holds\n'
  printf '%s\n' "$output" | sed 's/^/      /'
  printf '\n0 passed, 1 failed\n'
  exit 1
fi
