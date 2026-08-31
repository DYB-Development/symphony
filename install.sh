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
