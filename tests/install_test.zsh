#!/usr/bin/env zsh
# Tests for install.sh. Every case runs against a throwaway config directory so
# the machine's own Claude configuration is never touched.
#
# Usage: zsh tests/install_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
INSTALL="$ROOT/install.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  [[ "$1" == "$2" ]] && ok "$3" || { fail "$3"; printf '      want: %s\n      got:  %s\n' "$1" "$2"; }
}

fresh_config() {
  local d
  d="$(mktemp -d)"
  printf '%s' "$d"
}

echo "install.sh:"

CONFIG="$(fresh_config)"
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1

assert_equals "$ROOT/rules" "$(readlink "$CONFIG/rules")" \
  "links the rules directory at the package"

rm -rf "$CONFIG"

CONFIG="$(fresh_config)"
mkdir -p "$CONFIG/commands"
printf 'mine\n' > "$CONFIG/commands/my-own.md"
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1

assert_equals "$ROOT/commands/review.md" "$(readlink "$CONFIG/commands/review.md")" \
  "links each command file into the commands directory"

assert_equals "mine" "$(cat "$CONFIG/commands/my-own.md")" \
  "leaves a command it does not own untouched"

rm -rf "$CONFIG"

CONFIG="$(fresh_config)"
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1

assert_equals "SessionStart SubagentStart PostToolUse PreToolUse" \
  "$(jq -r '[.hooks | keys_unsorted[]] | join(" ")' "$CONFIG/settings.json" | tr '\n' ' ' | sed 's/ $//')" \
  "registers a hook for each event the package needs"

rm -rf "$CONFIG"

CONFIG="$(fresh_config)"
cat > "$CONFIG/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "mine.sh" } ] }
    ]
  }
}
JSON
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1

assert_equals "mine.sh" \
  "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$CONFIG/settings.json")" \
  "keeps a hook the person already had"

assert_equals "opus" "$(jq -r '.model' "$CONFIG/settings.json")" \
  "keeps settings that are not hooks"

rm -rf "$CONFIG"

CONFIG="$(fresh_config)"
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" >/dev/null 2>&1

assert_equals "1" \
  "$(jq '.hooks.PreToolUse | length' "$CONFIG/settings.json")" \
  "adds a hook once however often it runs"

assert_equals "0" \
  "$(find "$CONFIG" -name '*.backup' | wc -l | tr -d ' ')" \
  "backs nothing up when everything is already linked"

rm -rf "$CONFIG"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
