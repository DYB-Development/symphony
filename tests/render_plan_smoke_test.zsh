#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
RENDER="$SCRIPT_DIR/../bin/render-plan.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m–\033[0m %s\n' "$1"; }

echo "render-plan.sh against a real plan issue:"

if [[ "${RENDER_PLAN_SMOKE:-}" != */*#* ]]; then
  skip "RENDER_PLAN_SMOKE names no owner/repo#N plan issue, so nothing is rendered"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  exit 0
fi

page="$("$RENDER" "${RENDER_PLAN_SMOKE%%#*}" "${RENDER_PLAN_SMOKE##*#}")"
parts="$(printf '%s' "$page" | grep -o 'class="part"' | wc -l | tr -d ' ')"

if [[ "$parts" == 10 && "$page" != *MARKER-* ]]; then
  ok "a real plan renders all ten sections with nothing left unfilled"
else
  fail "a real plan renders all ten sections with nothing left unfilled"
  printf '      sections: %s\n' "$parts"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
