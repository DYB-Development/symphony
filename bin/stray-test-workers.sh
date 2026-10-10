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

any_still_running() {
  for pid in $asked; do
    kill -0 "$pid" 2>/dev/null && return 0
  done
  return 1
}

tries=$(( grace * 10 ))
while [ "$tries" -gt 0 ] && any_still_running; do
  sleep 0.1
  tries=$(( tries - 1 ))
done

for pid in $(stray); do
  kill -9 "$pid" 2>/dev/null || true
done
