#!/usr/bin/env bash
# Run every zsh test suite in this repo. Picks up new suites automatically —
# a file named <thing>_test.zsh anywhere under the repo root is a suite.
#
# Usage: ./run_tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RESULTS="$(mktemp -d)"
trap 'rm -rf "$RESULTS"' EXIT

run_suite() {
  local index="$1" suite="$2"
  zsh "$suite" > "$RESULTS/$index.out" 2>&1
  echo "$?" > "$RESULTS/$index.status"
}
export -f run_suite
export RESULTS

SEED="$RANDOM"
RANDOM="$SEED"
echo "Run options: --seed $SEED"
echo ""

SUITES=()
while IFS= read -r suite; do
  SUITES+=("$suite")
done < <(find "$ROOT" -name '*_test.zsh' -not -path '*/.git/*' | sort |
  while IFS= read -r suite; do echo "$RANDOM $suite"; done | sort -n | cut -d' ' -f2-)

for i in "${!SUITES[@]}"; do
  printf '%s\n%s\n' "$i" "${SUITES[$i]}"
done | xargs -n 2 -P "${PARALLEL_WORKERS:-$(getconf _NPROCESSORS_ONLN)}" bash -c 'run_suite "$1" "$2"' _

FAILED=()
for i in "${!SUITES[@]}"; do
  name="${SUITES[$i]#"$ROOT"/}"
  echo "── $name"
  cat "$RESULTS/$i.out"
  [ "$(cat "$RESULTS/$i.status")" = 0 ] || FAILED+=("$name")
  echo ""
done

if [ ${#FAILED[@]} -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi

echo "All suites passed."
