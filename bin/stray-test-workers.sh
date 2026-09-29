#!/usr/bin/env bash
set -euo pipefail

grace="${STRAY_TEST_WORKERS_GRACE:-5}"

stray() {
  ps -Ao pid=,ppid=,command= | awk '$2 == 1 && $3 == "Rails" && $4 == "test" && $5 == "worker" { print $1 }'
}

asked="$(stray)"
[ -n "$asked" ] || exit 0

for pid in $asked; do
  kill "$pid" 2>/dev/null || true
done

sleep "$grace"

for pid in $(stray); do
  kill -9 "$pid" 2>/dev/null || true
done
