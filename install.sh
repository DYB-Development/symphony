#!/usr/bin/env bash
#
# install.sh — link this package into place for Claude Code.
#
# Usage:
#   ./install.sh
#
# Set CLAUDE_CONFIG_DIR to install somewhere other than ~/.claude.
#
set -euo pipefail

SYMPHONY_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

usage() {
  cat <<'USAGE'
install.sh — put this package where Claude Code will find it.

There are two ways to install it, and you want one of them, not both.

usage: install.sh [--link | --plugin | --help]

  (no argument)   same as --link
  --link          symlink the rules, agents, scripts and commands into place,
                  and merge the hooks into your settings. Commands are run as
                  /review. Editing a file in this clone takes effect at once.
  --plugin        register this clone as a marketplace and install it as a
                  plugin. Commands are run as /symphony:review, and updates
                  come through claude plugin update.
  --help          print this and change nothing
USAGE
}

MODE="link"
case "${1:-}" in
  "")        MODE="link" ;;
  --link)    MODE="link" ;;
  --plugin)  MODE="plugin" ;;
  -h|--help) usage; exit 0 ;;
  *)         printf 'unrecognised argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
esac

link_file() {
  local src="$1" dest="$2"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "  skip   $dest (already linked)"
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "  backup $dest → ${dest}.backup"
    mv "$dest" "${dest}.backup"
  fi

  ln -s "$src" "$dest"
  echo "  link   $dest → $src"
}

if [ "$MODE" = plugin ]; then
  command -v claude >/dev/null || { echo "the claude CLI is required to install as a plugin" >&2; exit 1; }
  echo "Plugin:"
  claude plugin marketplace add "$SYMPHONY_DIR"
  claude plugin install symphony@symphony
  echo "  installed — its commands are namespaced, so a review is /symphony:review"
  exit 0
fi

mkdir -p "$CONFIG_DIR"

echo "Rules, agents and scripts:"
for dir in rules agents bin; do
  link_file "$SYMPHONY_DIR/$dir" "$CONFIG_DIR/$dir"
done

echo ""
echo "Commands:"
mkdir -p "$CONFIG_DIR/commands"
for cmd in "$SYMPHONY_DIR"/commands/*.md; do
  [ -e "$cmd" ] || continue
  link_file "$cmd" "$CONFIG_DIR/commands/$(basename "$cmd")"
done

echo ""
echo "Hooks:"
command -v jq >/dev/null || { echo "  jq is required to register the hooks" >&2; exit 1; }

SETTINGS="$CONFIG_DIR/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# One hooks file serves both installs: the plugin runtime substitutes
# CLAUDE_PLUGIN_ROOT itself, and a linked install substitutes it here.
ours="$(sed "s|\${CLAUDE_PLUGIN_ROOT}|$SYMPHONY_DIR|g" "$SYMPHONY_DIR/hooks/hooks.json" | jq '.hooks')"

merged="$(jq --argjson ours "$ours" '
  .hooks = reduce ($ours | to_entries[]) as $event ((.hooks // {});
    .[$event.key] = reduce (((.[$event.key] // []) + $event.value)[]) as $entry
      ([]; if index($entry) then . else . + [$entry] end))
' "$SETTINGS")"

printf '%s\n' "$merged" > "$SETTINGS"
echo "  merged into $SETTINGS"
