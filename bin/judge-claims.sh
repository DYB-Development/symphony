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

draft=$(jq -r '.draft' "$claims")
[ -r "$draft" ] ||
  { echo "judge-claims.sh: the draft $draft cannot be read, so nothing was judged" >&2; exit 70; }

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rules="$(awk '/^## What the judge is given/ { on = 1 } on' "$root/rules/claim-checking.md")"

ask=$(mktemp)
trap 'rm -f "$ask"' EXIT

{
  printf 'The draft:\n\n'
  cat "$draft"
  printf '\nThe claims:\n'

  count=$(jq '.claims | length' "$claims")
  index=0
  while [ "$index" -lt "$count" ]; do
    text=$(jq -r ".claims[$index].text" "$claims")
    commit=$(jq -r ".claims[$index].captured.commit // \"\"" "$claims")
    lines=$(jq -r ".claims[$index].captured.lines // \"\"" "$claims")
    path=$(jq -r ".claims[$index].pointer.path" "$claims")

    printf '\n%s. "%s"\n' "$((index + 1))" "$text"
    printf 'Lines captured at %s in %s:\n%s\n' "$commit" "$path" "$lines"
    printf 'File %s at that commit:\n' "$path"
    git show "$commit:$path" 2>/dev/null || printf '(the file could not be read)\n'

    index=$((index + 1))
  done
} > "$ask"

reply="$(claude -p --model opus --system-prompt "$rules" --tools "" --setting-sources "" --no-session-persistence --strict-mcp-config < "$ask")" ||
  { echo "judge-claims.sh: the judge's run failed, so nothing was judged" >&2; exit 70; }

printf '%s\n' "$reply"
