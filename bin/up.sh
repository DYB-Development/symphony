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

git pull -q --ff-only
