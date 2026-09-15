#!/usr/bin/env zsh
# Tests for bin/turn-sound.sh. Every case plays through a stand-in player that
# writes what it was asked to play, and keeps its off flag in a throwaway
# directory, so no sound plays and no real setting is touched.
#
# Usage: zsh tests/turn_sound_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SOUND="$SCRIPT_DIR/../bin/turn-sound.sh"

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

new_dir() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/turn_sound_test.XXXXXX")"
  PLAYER="$WORK/player"
  printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> "%s/played"\n' "$WORK" > "$PLAYER"
  chmod +x "$PLAYER"
}
drop_dir() { rm -rf "$WORK"; }

sound() {
  TURN_SOUND_DIR="$WORK" TURN_SOUND_PLAYER="$PLAYER" TURN_SOUND_FILE="/sounds/Glass.aiff" "$SOUND" "$@"
}

played() { cat "$WORK/played" 2>/dev/null; }

echo "turn-sound.sh play:"

new_dir
echo '{"hook_event_name":"Stop"}' | sound play
assert_equals "/sounds/Glass.aiff" "$(played)" "plays the sound when a session waits on the user"
drop_dir

new_dir
sound off
echo '{"hook_event_name":"Stop"}' | sound play
assert_equals "" "$(played)" "plays nothing once turned off"
drop_dir

new_dir
sound off
sound on
echo '{"hook_event_name":"Stop"}' | sound play
assert_equals "/sounds/Glass.aiff" "$(played)" "plays again once turned back on"
drop_dir

new_dir
echo '{"hook_event_name":"Stop"}' | TURN_SOUND_DIR="$WORK" TURN_SOUND_PLAYER="$WORK/no-such-player" "$SOUND" play 2>/dev/null
assert_equals "0" "$?" "exits cleanly on a machine with no player"
drop_dir

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
