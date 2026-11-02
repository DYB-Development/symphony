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
ledger="${TEST_SLOTS_DIR:-$HOME/.claude/test-slots}"
leases="$ledger/leases"

started_at() {
  local started
  started=$(ps -o lstart= -p "$1" 2>/dev/null) || return 0
  echo $started
}

held_slots() {
  local file pid started slots held=0
  for file in "$leases"/*; do
    [ -f "$file" ] || continue
    { read -r pid; read -r started; read -r slots; } < "$file"
    [ "$(started_at "$pid")" = "$started" ] && held=$((held + slots))
  done
  echo "$held"
}

take_slots() {
  local holder=$1 free
  free=$((total - $(held_slots)))
  [ "$free" -ge 2 ] || free=2
  printf '%s\n%s\n%s\n' "$holder" "$(started_at "$holder")" "$free" > "$leases/$holder"
  echo "$free"
}

run() {
  local slots
  mkdir -p "$leases"
  slots=$(lockf -k "$ledger/lock" "$0" take $$)
  trap 'rm -f "$leases/$$"' EXIT
  PARALLEL_WORKERS="$slots" "$@"
}

case "${1:-}" in
  run) shift; [ $# -ge 1 ] || usage; run "$@" ;;
  take) [ $# -eq 2 ] || usage; take_slots "$2" ;;
  *) usage ;;
esac
