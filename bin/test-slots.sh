#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: test-slots.sh run <command> [<argument>...]

Runs a test command with PARALLEL_WORKERS set to the slots it takes from the
machine's shared total.
USAGE
  exit 64
}

total="${TEST_SLOTS_TOTAL:-$(getconf _NPROCESSORS_ONLN)}"

run() {
  PARALLEL_WORKERS="$total" "$@"
}

case "${1:-}" in
  run) shift; [ $# -ge 1 ] || usage; run "$@" ;;
  *) usage ;;
esac
