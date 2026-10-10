#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: up

Gets the Rails app in the current folder running in the browser. In the app's
main clone it first pulls the latest commits of the checked-out branch.
USAGE
  exit 64
}

[ $# -eq 0 ] || usage

port_in_use() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

first_free_port() {
  local port=3000
  while port_in_use "$port"; do port=$((port + 1)); done
  echo "$port"
}

in_main_clone() {
  [ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ]
}

if in_main_clone; then
  git pull -q --ff-only || {
    echo "up: the pull failed, so the app was not set up or started" >&2
    exit 1
  }
fi

bin/setup --skip-server

port="$(first_free_port)"
address="http://localhost:$port"

PORT="$port" bin/dev &
server=$!

until curl -s -o /dev/null "$address"; do
  kill -0 "$server" 2>/dev/null || {
    echo "up: the server stopped before it answered at $address" >&2
    exit 1
  }
  sleep 0.5
done

open "$address"
wait "$server"
