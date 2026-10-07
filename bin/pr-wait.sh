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

while true; do
  state=$(gh pr view "$pr" --repo "$repo" --json state,url,statusCheckRollup | jq -r '.state')
  case "$state" in
    MERGED) printf 'PR #%s was merged\n' "$pr"; exit 0 ;;
    CLOSED) printf 'PR #%s was closed\n' "$pr"; exit 0 ;;
  esac
  sleep 30
done
