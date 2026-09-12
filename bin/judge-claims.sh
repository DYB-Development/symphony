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

claims=$1

[ -r "$claims" ] ||
  { echo "judge-claims.sh: $claims cannot be read, so nothing was judged" >&2; exit 70; }

jq -e '.claims | type == "array"' "$claims" >/dev/null 2>&1 ||
  { echo "judge-claims.sh: $claims names no claims to judge, so nothing was judged" >&2; exit 70; }
