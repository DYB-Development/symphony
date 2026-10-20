#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh --rows | effort.sh
       usage.sh --rows | effort.sh --render

Totals what the owner put into this branch from the rows `usage.sh --rows`
prints on standard input. `--render` prints the PR body's Effort section from
those totals, and says `Not measured.` when no row names this branch.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

case "${1:-}" in
  "" | --render) ;;
  *) usage ;;
esac

format=$(cat "$(dirname "$0")/format.awk")

totals=$(awk -F '\t' -v idle_cap=600 "$format"'
  { total[$3] += $4 }
  $3 == "prompt" && !seen[$2]++ { sessions++ }
  $3 == "waited" { active += $4 < idle_cap ? $4 : idle_cap }
  END {
    if (NR == 0) exit
    printf "Sessions: %d\n", sessions
    printf "Prompts: %d\n", total["prompt"]
    printf "Words typed: %s\n", grouped(total["typed"])
    printf "Pasted blocks: %s\n", grouped(total["pasted"])
    printf "Words pasted: %s\n", grouped(total["pasted-words"])
    printf "Questions answered: %s\n", grouped(total["answered"])
    printf "Interruptions: %s\n", grouped(total["interrupted"])
    printf "Rejected tool calls: %s\n", grouped(total["rejected"])
    printf "Claude working time: %s\n", duration(int(total["turn"] / 60000))
    printf "Your active time: %s\n", duration(int(active / 60))
  }
')

if [ "${1:-}" = "--render" ]; then
  printf '## Effort\n\n'
  if [ -n "$totals" ]; then
    printf '%s\n' "$totals" | sed 's/^/- /'
  else
    printf 'Not measured.\n'
  fi
  exit 0
fi

printf '%s\n' "${totals:-No effort recorded for this branch.}"
