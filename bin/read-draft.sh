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

claude -p --system-prompt "$rules" --tools "" --setting-sources "" --no-session-persistence < "$draft"
