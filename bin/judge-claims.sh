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

standing=$(printf '%s\n' "$reply" | awk 'NF { last = $0 } END { print last }')
fell=0

printf '%s' "$standing" | grep -qx 'Standing: [0-9][0-9]*' ||
  { echo "judge-claims.sh: the judge's reply does not end with a count, so nothing was judged" >&2; exit 70; }

index=0
while [ "$index" -lt "$count" ]; do
  text=$(jq -r ".claims[$index].text" "$claims")

  block=$(printf '%s\n' "$reply" | awk -v want="$text" '
    on && /^[0-9]+\. / { exit }
    index($0, "\"" want "\"") && /^[0-9]+\. / { on = 1; next }
    on && verdict == "" && /Verdict:/ { sub(/^ *Verdict: */, ""); verdict = $0; next }
    on && why == "" && /Why:/ { sub(/^ *Why: */, ""); why = $0; next }
    END { if (verdict != "") print verdict "\t" why }
  ')

  verdict=$(printf '%s' "$block" | cut -f1)
  why=$(printf '%s' "$block" | cut -f2)

  case "$verdict" in
    supported|unsupported|refuted) ;;
    *)
      echo "judge-claims.sh: no verdict came back for a claim, so nothing was judged" >&2
      exit 70
      ;;
  esac

  [ "$verdict" = supported ] || fell=$((fell + 1))

  updated=$(jq --argjson i "$index" --arg stands "$verdict" --arg why "$why" \
    '.claims[$i].verdict = { stands: $stands, why: $why }' "$claims")
  printf '%s\n' "$updated" > "$claims"

  index=$((index + 1))
done

uncited=$(printf '%s\n' "$reply" | awk '
  /^Uncited:/ { on = 1; next }
  on && /^Standing:/ { exit }
  on && /^- / { sub(/^- /, ""); sub(/^"/, ""); sub(/"$/, ""); print }
')

if [ -n "$uncited" ]; then
  listed=$(printf '%s\n' "$uncited" | jq -R . | jq -s .)
else
  listed='[]'
fi

updated=$(jq --argjson listed "$listed" '.uncited = $listed' "$claims")
printf '%s\n' "$updated" > "$claims"

[ -z "$uncited" ] || fell=$((fell + 1))

[ "$fell" -eq 0 ] || exit 1
