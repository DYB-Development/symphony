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

assert_contains() {
  [[ "$2" == *"$1"* ]] && ok "$3" || { fail "$3"; printf '      wanted to find: %s\n' "$1"; }
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

assert_equals "hooks" \
  "$(jq -r 'keys_unsorted[0]' "$ROOT/hooks/hooks.json" 2>/dev/null)" \
  "keeps the hooks where a plugin expects them, in the shape a plugin expects"

assert_equals "symphony" \
  "$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)" \
  "declares itself a plugin named symphony, so its commands namespace under it"

CONFIG="$(fresh_config)"
CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" --no-such-mode >/dev/null 2>&1
assert_equals "64" "$?" "refuses a mode it does not recognise"

CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" --help >/dev/null 2>&1
assert_equals "0" "$?" "prints help without failing"

assert_equals "" "$(ls "$CONFIG" 2>/dev/null)" \
  "installs nothing while printing help"
rm -rf "$CONFIG"

# A stub claude on PATH, so plugin mode cannot register a marketplace or
# install anything on the machine running the suite.
STUB="$(mktemp -d "${TMPDIR:-/tmp}/install_test_stub.XXXXXX")"
cat > "$STUB/claude" <<'CLAUDE'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$STUB_LOG"
CLAUDE
chmod +x "$STUB/claude"
export STUB_LOG="$STUB/calls.log"

CONFIG="$(fresh_config)"
PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$CONFIG" "$INSTALL" --plugin >/dev/null 2>&1

assert_contains "plugin marketplace add $ROOT" "$(cat "$STUB_LOG")" \
  "registers this clone as a marketplace"

assert_contains "plugin install symphony@symphony" "$(cat "$STUB_LOG")" \
  "installs the plugin from it"

assert_equals "" "$(readlink "$CONFIG/rules")" \
  "links nothing, because the plugin carries its own files"

rm -rf "$CONFIG" "$STUB"
unset STUB_LOG

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
