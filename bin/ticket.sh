#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ticket.sh "<reference>"
       ticket.sh --render

Appends one ticket reference to .ticket at the repo root, creating it if absent
and recording a repeated reference once. `--render` prints the PR body's Ticket
Billed Against section from those references, and says `Not specified.` when
there are none.
The file is gitignored and is deleted when the branch's PR merges.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

root=$(git rev-parse --show-toplevel) || {
  echo "ticket.sh: not inside a git repository" >&2
  exit 69
}

file="$root/.ticket"

if [ "${1:-}" = "--render" ]; then
  printf '## Ticket Billed Against\n\n'
  if [ -s "$file" ]; then
    sed 's/^/- /' "$file"
  else
    printf 'Not specified.\n'
  fi
  exit 0
fi

[ $# -eq 1 ] || usage
[ -n "${1// }" ] || usage

ticket=$1

grep -qxF "$ticket" "$file" 2>/dev/null || printf '%s\n' "$ticket" >> "$file"

echo "$file"
