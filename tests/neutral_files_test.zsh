#!/usr/bin/env zsh
# Tests that no file this package ships names a person, an account or a private
# repository.
#
# The terms are supplied by whoever runs the suite and are never tracked here: a
# list of names committed to this repo would carry the very identifiers the
# check exists to keep out. Point SYMPHONY_IDENTIFIERS at a file of one term per
# line, or keep one at ~/.config/symphony/identifiers.txt. With neither in
# place there is nothing to check and the suite says so.
#
# A term is matched case-sensitively when it contains an uppercase letter, and
# case-insensitively otherwise, so a bare given name is caught without flagging
# an account it forms part of.
#
# Usage: zsh tests/neutral_files_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
LIST="${SYMPHONY_IDENTIFIERS:-$HOME/.config/symphony/identifiers.txt}"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m–\033[0m %s\n' "$1"; }

occurrences_of() {
  local term="$1" flags='-nEw'
  [[ "$term" == *[A-Z]* ]] || flags='-nEwi'
  local f
  while IFS= read -r f; do
    grep $flags -- "$term" "$ROOT/$f" 2>/dev/null | while IFS= read -r m; do
      printf '%s:%s\n' "$f" "${m%%:*}"
    done
  done < <(git -C "$ROOT" ls-files)
}

echo "shipped files name nobody:"

if [[ ! -r "$LIST" ]]; then
  skip "no identifier list configured, nothing to check"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  exit 0
fi

while IFS= read -r term; do
  [[ -n "$term" ]] || continue
  found=("${(@f)$(occurrences_of "$term")}")
  found=("${(@)found:#}")
  if [[ ${#found[@]} -eq 0 ]]; then
    ok "no shipped file names the configured term"
  else
    fail "no shipped file names the configured term"
    printf '      %s\n' "${found[@]}"
  fi
done < "$LIST"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
