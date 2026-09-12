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

claims=$1
repo=$2
pr=$3

[ -r "$claims" ] ||
  { echo "capture-evidence.sh: $claims cannot be read, so nothing was captured" >&2; exit 70; }

jq -e . "$claims" >/dev/null 2>&1 ||
  { echo "capture-evidence.sh: $claims is not readable as a claims file, so nothing was captured" >&2; exit 70; }

commits=$(gh pr view "$pr" --repo "$repo" --json headRefOid,baseRefOid --jq '[.headRefOid, .baseRefOid] | @tsv') ||
  { echo "capture-evidence.sh: the pull request $repo#$pr could not be read, so nothing was captured" >&2; exit 70; }

head_commit=$(printf '%s' "$commits" | cut -f1)
base_commit=$(printf '%s' "$commits" | cut -f2)

count=$(jq '.claims | length' "$claims")
index=0
unresolved=0

while [ "$index" -lt "$count" ]; do
  pointer=$(jq -c ".claims[$index].pointer" "$claims")
  path=$(printf '%s' "$pointer" | jq -r .path)
  from=$(printf '%s' "$pointer" | jq -r .from)
  to=$(printf '%s' "$pointer" | jq -r .to)
  side=$(printf '%s' "$pointer" | jq -r .side)

  commit=$head_commit
  [ "$side" = LEFT ] && commit=$base_commit

  if ! file_at_commit=$(git show "$commit:$path" 2>/dev/null); then
    printf 'unresolved  %s is not at %s\n' "$path" "$commit"
    unresolved=1
    index=$((index + 1))
    continue
  fi

  lines=$(printf '%s\n' "$file_at_commit" | sed -n "${from},${to}p")

  claims_json=$(jq --argjson i "$index" --arg commit "$commit" --arg lines "$lines" \
    '.claims[$i].captured = { commit: $commit, lines: $lines }' "$claims")
  printf '%s\n' "$claims_json" > "$claims"

  index=$((index + 1))
done

[ "$unresolved" -eq 0 ] || exit 1
