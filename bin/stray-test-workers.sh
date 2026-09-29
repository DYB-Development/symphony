#!/usr/bin/env bash
set -euo pipefail

ps -Ao pid=,ppid=,command= | awk '$2 == 1 && $3 == "Rails" && $4 == "test" && $5 == "worker" { print $1 }' |
  while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done
