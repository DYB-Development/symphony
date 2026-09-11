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

reply="$(claude -p --system-prompt "$rules" --tools "" --setting-sources "" --no-session-persistence --strict-mcp-config < "$draft")" ||
  { echo "read-draft.sh: the reader's run failed, so nothing was read" >&2; exit 70; }
printf '%s\n' "$reply"

count="$(printf '%s\n' "$reply" | awk 'NF { last = $0 } END { print last }')"

printf '%s' "$count" | grep -qx 'Flagged: [0-9][0-9]*' ||
  { echo "read-draft.sh: the reader's reply does not end with a count of flagged sentences" >&2; exit 70; }

[ "$count" = "Flagged: 0" ] || exit 1
