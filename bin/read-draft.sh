#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: read-draft.sh <draft-file>

Hands the draft to a reader who has seen nothing else, and prints what the
reader understood each sentence to say.
See ~/.claude/rules/draft-reading.md.
USAGE
  exit 64
}

[ $# -eq 1 ] || usage

draft=$1
[ -f "$draft" ] || { echo "read-draft.sh: $draft is not there" >&2; exit 66; }

here="$(dirname "$0")"
rules="$(cat "$here/../rules/draft-reading.md")"

reply="$(claude -p --system-prompt "$rules" --tools "" --setting-sources "" --no-session-persistence --strict-mcp-config < "$draft")"

printf '%s\n' "$reply" | grep -q '^Flagged: [0-9][0-9]*$' ||
  { echo "read-draft.sh: the reader's reply carries no count of flagged sentences" >&2; exit 70; }

printf '%s\n' "$reply" | grep -q '^Flagged: 0$' || exit 1
