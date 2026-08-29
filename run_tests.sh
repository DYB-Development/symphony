#!/usr/bin/env bash
# Run every zsh test suite in this repo. Picks up new suites automatically —
# a file named <thing>_test.zsh anywhere under the repo root is a suite.
#
# Usage: ./run_tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

FAILED=()

while IFS= read -r suite; do
  echo "── ${suite#"$ROOT"/}"
  if ! zsh "$suite"; then
    FAILED+=("${suite#"$ROOT"/}")
  fi
  echo ""
done < <(find "$ROOT" -name '*_test.zsh' -not -path '*/.git/*' | sort)

if [ ${#FAILED[@]} -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi

echo "All suites passed."
