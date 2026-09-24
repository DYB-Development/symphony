#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh --rows | effort.sh

Totals what the owner put into this branch from the rows `usage.sh --rows`
prints on standard input.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

[ $# -eq 0 ] || usage

awk -F '\t' '
  { total[$3] += $4 }
  $3 == "prompt" && !seen[$2]++ { sessions++ }
  END {
    printf "Sessions: %d\n", sessions
    printf "Prompts: %d\n", total["prompt"]
  }
'
