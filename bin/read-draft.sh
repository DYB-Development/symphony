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
overlay="${SYMPHONY_OVERLAY_DIR:-$HOME/.config/symphony/rules}/draft-reading.md"
[ -f "$overlay" ] && rules_file="$overlay" || rules_file="$here/../rules/draft-reading.md"
rules="$(awk '/^## What the scribe does with it/ { exit } { print }' "$rules_file")"

reply="$("$here/ask-model.sh" read-draft opus 'Flagged: [0-9]+' "$rules" < "$draft")" || exit 70
printf '%s\n' "$reply"

count="$(printf '%s\n' "$reply" | awk 'NF { last = $0 } END { print last }')"

[ "$count" = "Flagged: 0" ] || exit 1
