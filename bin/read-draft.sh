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
