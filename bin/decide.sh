#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: decide.sh "<question>" "<decision>"
       decide.sh --render

Appends one entry to .decisions.md at the repo root, creating it if absent.
`--render` prints the PR body's Decision Log section from those entries,
verbatim, and exits 1 when there is no log.
The file is gitignored and is deleted when the branch's PR merges.
See ~/.claude/rules/decision-log.md.
USAGE
  exit 64
}

root=$(git rev-parse --show-toplevel) || {
  echo "decide.sh: not inside a git repository" >&2
  exit 69
}

log="$root/.decisions.md"

if [ "${1:-}" = "--render" ]; then
  [ $# -eq 1 ] || usage
  [ -f "$log" ] || exit 1
  printf '## Decision Log\n'
  awk '/^## /{ printf "\n### %s\n\n", substr($0, 4); next } NR > 1 && NF { print "> " $0 }' "$log"
  exit 0
fi

[ $# -eq 2 ] || usage
[ -n "${1// }" ] && [ -n "${2// }" ] || usage

question=$1
decision=$2

[ -f "$log" ] || printf '# Decisions\n' > "$log"

printf '\n## %s\n%s\n' "${question%$'\n'}" "${decision%$'\n'}" >> "$log"

echo "$log"
