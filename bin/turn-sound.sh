#!/usr/bin/env bash
set -euo pipefail

player="${TURN_SOUND_PLAYER:-afplay}"
sound_file="${TURN_SOUND_FILE:-/System/Library/Sounds/Glass.aiff}"
off_flag="${TURN_SOUND_DIR:-$HOME/.claude}/turn-sound-off"

case "${1:-}" in
  play)
    cat >/dev/null
    [ -e "$off_flag" ] && exit 0
    command -v "$player" >/dev/null || exit 0
    "$player" "$sound_file"
    ;;
  off)
    mkdir -p "$(dirname "$off_flag")"
    touch "$off_flag"
    ;;
  on)
    rm -f "$off_flag"
    ;;
esac
