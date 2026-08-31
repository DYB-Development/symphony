#!/usr/bin/env zsh
# Tests that no file this package ships names a person, an account or a private
# repository. Every term in forbidden-identifiers.txt is searched for across the
# tracked files, so a name that reappears fails here rather than reaching
# whoever installs the package.
#
# A term is matched case-sensitively when it contains an uppercase letter, and
# case-insensitively otherwise, so a bare given name is caught without flagging
# the account it forms part of.
#
# Usage: zsh tests/neutral_files_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
LIST="$SCRIPT_DIR/forbidden-identifiers.txt"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

# The list names the terms, so it is the one tracked file that may contain them.
scanned() {
  git -C "$ROOT" ls-files | grep -vFx "${LIST#"$ROOT"/}"
}

occurrences_of() {
  local term="$1" flags='-nEw'
  [[ "$term" == *[A-Z]* ]] || flags='-nEwi'
  local f
  while IFS= read -r f; do
    grep $flags -- "$term" "$ROOT/$f" 2>/dev/null | while IFS= read -r m; do
      printf '%s:%s\n' "$f" "${m%%:*}"
    done
  done < <(scanned)
}

echo "shipped files name nobody:"

while IFS= read -r term; do
  [[ -n "$term" ]] || continue
  found=("${(@f)$(occurrences_of "$term")}")
  found=("${(@)found:#}")
  if [[ ${#found[@]} -eq 0 ]]; then
    ok "no shipped file names \"$term\""
  else
    fail "no shipped file names \"$term\""
    printf '      %s\n' "${found[@]}"
  fi
done < "$LIST"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
