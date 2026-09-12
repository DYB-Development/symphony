#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: judge-claims.sh <claims.json>

Hands each claim and the lines captured for it to a reader that did not write
the draft, and records whether the evidence bears the claim out.

Exits 0 when every claim stands, 1 when any does not, and 70 when the judging
could not be done.
See ~/.claude/rules/claim-checking.md.
USAGE
  exit 64
}

[ $# -eq 1 ] || usage
