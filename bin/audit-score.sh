#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: audit-score.sh <audit.json>
       audit-score.sh <earlier-audit.json> <later-audit.json>

Computes what each area of an audit costs to carry, from the cost band and
horizon its findings record and the weights in the rubric. Lower is better, and
the number is unbounded — it is what that area costs at the moment it was
measured, not a total owed.

Given two audit files it prints the movement per area between them.

The score is computed here and never written by a scribe. See
~/.claude/rules/repo-audit.md and ~/.claude/rules/audit-rubric.json.
USAGE
  exit 64
}

[ $# -eq 1 ] || [ $# -eq 2 ] || usage

here="$(dirname "$0")"
rubric="${AUDIT_RUBRIC_FILE:-$here/../rules/audit-rubric.json}"

refuse() {
  echo "audit-score.sh: $1" >&2
  exit 65
}

for f in "$@"; do
  [ -s "$f" ] || refuse "no audit file at $f"
  [ "$(jq '[ .checks[].findings[] | has("score") ] | any' "$f")" = "false" ] ||
    refuse "$f already carries a score, and a score is computed here rather than written by a scribe"
done

if [ $# -eq 2 ]; then
  a=$(jq -r '.rubricVersion' "$1")
  b=$(jq -r '.rubricVersion' "$2")
  [ "$a" = "$b" ] ||
    refuse "these audits were scored under rubric versions $a and $b, so their numbers are not comparable"
fi

score_by_area() {
  jq -r --slurpfile r "$rubric" '
    [ .checks[].findings[] ] as $f
    | reduce $f[] as $x ({};
        .[$x.area] as $a
        | .[$x.area] = {
            score: (($a.score // 0)
              + ($r[0].cost[$x.cost].weight * $r[0].horizon[$x.horizon].multiplier)),
            count: (($a.count // 0) + 1)
          })
    | to_entries | sort_by(-.value.score)[]
    | "\(.key)\t\(.value.score)\t\(.value.count)"
  ' "$1"
}

if [ $# -eq 1 ]; then
  printf 'area  score  findings\n'
  score_by_area "$1" | while IFS=$'\t' read -r area score count; do
    printf '%s  %.1f  %s\n' "$area" "$score" "$count"
  done
  exit 0
fi

printf 'area  before  after  moved\n'
join -a1 -a2 -e 0 -o 0,1.2,2.2 -t $'\t' \
  <(score_by_area "$1" | cut -f1,2 | sort -t $'\t' -k1,1) \
  <(score_by_area "$2" | cut -f1,2 | sort -t $'\t' -k1,1) \
  | while IFS=$'\t' read -r area before after; do
      printf '%s  %.1f → %.1f  %+.1f\n' "$area" "$before" "$after" \
        "$(printf '%s' "$after - $before" | bc -l)"
    done
