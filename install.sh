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
