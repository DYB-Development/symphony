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

ledger=$1
[ -r "$ledger" ] ||
  { echo "check-citations.sh: $ledger cannot be read, so nothing was checked" >&2; exit 70; }

jq -e . "$ledger" >/dev/null 2>&1 ||
  { echo "check-citations.sh: $ledger is not readable as a ledger, so nothing was checked" >&2; exit 70; }

failed=0

while IFS= read -r citation; do
  commit=$(printf '%s' "$citation" | jq -r .commit)
  path=$(printf '%s' "$citation" | jq -r .path)
  from=$(printf '%s' "$citation" | jq -r .from)
  to=$(printf '%s' "$citation" | jq -r .to)
  quote=$(printf '%s' "$citation" | jq -r .quote)

  source_lines=$(git show "$commit:$path" 2>/dev/null | sed -n "${from},${to}p") || source_lines=""

  if [ "$source_lines" = "$quote" ]; then
    printf 'pass  %s:%s-%s\n' "$path" "$from" "$to"
  else
    printf 'fail  %s:%s-%s\n' "$path" "$from" "$to"
    failed=1
  fi
done < <(jq -c '.claims[].evidence[] | select(.kind == "lines")' "$ledger")

[ "$failed" -eq 0 ] || exit 1
