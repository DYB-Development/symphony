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
  function grouped(number,   digits, out) {
    digits = sprintf("%d", number)
    while (length(digits) > 3) {
      out = "," substr(digits, length(digits) - 2) out
      digits = substr(digits, 1, length(digits) - 3)
    }
    return digits out
  }

  { total[$3] += $4 }
  $3 == "prompt" && !seen[$2]++ { sessions++ }
  END {
    printf "Sessions: %d\n", sessions
    printf "Prompts: %d\n", total["prompt"]
    printf "Words typed: %s\n", grouped(total["typed"])
    printf "Pasted blocks: %s\n", grouped(total["pasted"])
    printf "Words pasted: %s\n", grouped(total["pasted-words"])
  }
'
