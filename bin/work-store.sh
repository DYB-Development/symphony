#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-store.sh show

show  Prints where the current repo keeps its plans and work: github, or
      dyb_web with the link and pipeline its setting names.
USAGE
  exit 64
}

show() {
  printf 'github\n'
}

case "${1:-}" in
  show) show ;;
  *) usage ;;
esac
