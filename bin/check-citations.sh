#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: check-citations.sh <ledger.json>

Compares every citation in a claim ledger with the source it names, with no
model taking part. Exits 0 when every citation passes, 1 when any fails, and 70
when a source could not be read.
See ~/.claude/rules/claim-checking.md.
USAGE
  exit 64
}

[ $# -eq 1 ] || usage
