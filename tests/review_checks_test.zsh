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

marker_for() {
  awk '/^## How a check is reported/ { on = 1; next } /^## / { on = 0 } on' "$RULES/review-checks.md" \
    | grep -F -- "**$1**" | grep -oE '^- [^ ]+' | sed 's/^- //'
}

typeset -A MARKERS
MARKERS=("a finding" "❌" "nothing found" "✅" "nothing to check" "✅")

for result marker in "${(@kv)MARKERS}"; do
  if [[ "$(marker_for "$result")" == "$marker" ]]; then
    ok "review-checks.md marks $result with $marker"
  else
    fail "review-checks.md marks $result with $marker"
  fi
done

unmarked=()
for c in "${CHECKS[@]}"; do
  grep -qF -- "- <✅ or ❌> **$c** —" "$RULES/pr-review.md" || unmarked+=("$c")
done
if [[ ${#unmarked[@]} -eq 0 ]]; then
  ok "every Findings bullet in pr-review.md opens with its marker"
else
  fail "every Findings bullet in pr-review.md opens with its marker"
  printf '      unmarked: %s\n' "${(j:, :)unmarked}"
fi

report_section="$(awk '/^## What the report says/ { on = 1; next } /^## / { on = 0 } on' "$RULES/repo-audit.md")"
if [[ "$report_section" == *"❌"* && "$report_section" == *"✅"* ]]; then
  ok "repo-audit.md opens each check in the report with its marker"
else
  fail "repo-audit.md opens each check in the report with its marker"
fi

scribe_summary_step="$(awk '/^6\. \*\*Write the summary\*\*/ { on = 1 } /^7\. / { on = 0 } on' "$SCRIPT_DIR/../agents/review-scribe.md")"
if [[ "$scribe_summary_step" == *"❌"* && "$scribe_summary_step" == *"✅"* ]]; then
  ok "review-scribe.md opens each Findings bullet with its marker"
else
  fail "review-scribe.md opens each Findings bullet with its marker"
fi

ci_section="$(awk '/^## What CI checks/ { on = 1; next } /^## / { on = 0 } on' "$RULES/pr-review.md")"
if [[ -n "${ci_section//[[:space:]]/}" ]]; then
  ok "pr-review.md keeps what CI checks out of a review"
else
  fail "pr-review.md keeps what CI checks out of a review"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
