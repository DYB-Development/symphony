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
