#!/usr/bin/env bash
set -euo pipefail

player="${TURN_SOUND_PLAYER:-afplay}"
sound_file="${TURN_SOUND_FILE:-/System/Library/Sounds/Glass.aiff}"

case "${1:-}" in
  play)
    cat >/dev/null
    "$player" "$sound_file"
    ;;
esac
