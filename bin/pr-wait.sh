#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pr-wait.sh <owner/repo> <pr-number>

Waits on one pull request with no model running. It opens the pull request in
the browser once every CI check passes, exits naming the check that failed when
one fails, and otherwise exits saying whether the pull request was merged or
closed. Start it as a background command right after the pull request opens, so
the session that started it is woken when it exits.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

repo=$1 pr=$2
opened=0

while true; do
  IFS=$'\t' read -r state url _ checks < <("$(dirname "${BASH_SOURCE[0]}")/pr-state.sh" "$pr" "$repo")
  case "$state" in
    MERGED) printf 'PR #%s was merged\n' "$pr"; exit 0 ;;
    CLOSED) printf 'PR #%s was closed\n' "$pr"; exit 0 ;;
  esac
  if [[ "$checks" == failed:* ]]; then
    printf 'CI failed on PR #%s: %s\n' "$pr" "${checks#failed: }"
    exit 1
  fi
  if [ "$opened" -eq 0 ] && [ "$checks" = passed ]; then
    open "$url"
    printf 'CI passed on PR #%s, opened it\n' "$pr"
    opened=1
  fi
  sleep 30
done
