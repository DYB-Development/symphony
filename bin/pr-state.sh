#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pr-state.sh <branch or number> [<owner/repo>]

Reads one pull request from GitHub and prints one line, separated by tabs: its
state (OPEN, MERGED or CLOSED), its address, its number, and its checks as
passed, pending, or failed: followed by the names of the checks that failed.
Every script that needs a pull request's state reads it through this one.
USAGE
  exit 64
}

[ $# -eq 1 ] || [ $# -eq 2 ] || usage

gh pr view "$1" ${2:+--repo "$2"} --json state,url,number,statusCheckRollup | jq -r '
  [.statusCheckRollup // [] | .[] | select(.conclusion == "FAILURE" or .conclusion == "CANCELLED" or .conclusion == "TIMED_OUT") | .name] as $failed
  | (if ($failed | length) > 0 then "failed: " + ($failed | join(", "))
     elif ((.statusCheckRollup // []) | length) > 0 and all(.statusCheckRollup[]; .conclusion == "SUCCESS") then "passed"
     else "pending" end) as $checks
  | [.state, .url, (.number | tostring), $checks] | @tsv'
