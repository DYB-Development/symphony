#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: up [phone]

Gets the Rails app in the current folder running in the browser. In the app's
main clone it first pulls the latest commits of the checked-out branch. With
phone, it starts the app with bin/phone so a phone can open it.
USAGE
  exit 64
}

start_command=bin/dev
case "$*" in
  "") ;;
  phone) start_command=bin/phone ;;
  *) usage ;;
esac

[ -x bin/setup ] && [ -x bin/dev ] || {
  echo "up: $PWD holds no app up knows how to start, which needs bin/setup and bin/dev" >&2
  exit 65
}

[ -x "$start_command" ] || {
  echo "up: $PWD has no phone start command, which needs bin/phone" >&2
  exit 65
}

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

PORT="$port" "$start_command" &
server=$!
trap 'kill "$server" 2>/dev/null' EXIT

until curl -s -o /dev/null "$address"; do
  kill -0 "$server" 2>/dev/null || {
    echo "up: the server stopped before it answered at $address" >&2
    exit 1
  }
  sleep 0.5
done

[ "$start_command" = bin/phone ] || open "$address"
wait "$server"
