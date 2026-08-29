#!/usr/bin/env zsh
# Tests that every check defined in claude/rules/review-checks.md is named by
# each reader that reports it. A check added to the list and reported by nobody
# fails here rather than being noticed months later.
#
# Usage: zsh zsh/review_checks_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
RULES="$SCRIPT_DIR/../rules"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

# The checks are the bold names under the "## The checks" heading.
checks_in() {
  awk '/^## The checks/ { on = 1; next } /^## / { on = 0 } on' "$1" \
    | grep -oE '^\*\*[^*]+\*\* —' | sed 's/^\*\*//; s/\*\* —$//'
}

reported_by() {
  grep -qF "$1" "$2"
}

echo "review-checks.md:"

CHECKS=("${(@f)$(checks_in "$RULES/review-checks.md")}")

if [[ ${#CHECKS[@]} -eq 0 ]]; then
  fail "the checks file names at least one check"
else
  ok "the checks file names ${#CHECKS[@]} checks"
fi

for reader in pr-review repo-audit; do
  missing=()
  for c in "${CHECKS[@]}"; do
    reported_by "$c" "$RULES/$reader.md" || missing+=("$c")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "every check is named in $reader.md"
  else
    fail "every check is named in $reader.md"
    printf '      not named: %s\n' "${(j:, :)missing}"
  fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
