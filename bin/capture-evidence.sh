#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: capture-evidence.sh <claims.json> <owner/repo> <pr-number>

Resolves every claim pointer against the source and writes what it read back
into the claims file. The right side of a pointer is read at the pull request's
head commit and the left side at its base commit.

Exits 0 when every pointer resolves, 1 when any does not, and 70 when a source
could not be read.
See ~/.claude/rules/claim-checking.md.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage
