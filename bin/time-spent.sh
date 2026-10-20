#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh --spans | time-spent.sh --render

Prints the PR body's Time Spent section from the spans `usage.sh --spans`
prints on standard input: the total, then one line per kind of work.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

[ "${1:-}" = "--render" ] || usage

work=$(mktemp -d "${TMPDIR:-/tmp}/time-spent.XXXXXX")
trap 'rm -rf "$work"' EXIT

awk -F '\t' '
  BEGIN { OFS = "\t" }
  $4 == "tool" && $5 ~ /-scribe$/ { print $1, $2, $5; next }
  $4 == "tool" && $6 == "Agent" && $7 ~ /-scribe$/ { print $1, $2, $7; next }
  $4 == "tool" && $6 == "Agent" { print $1, $2, "run"; next }
  $4 == "tool" { print $1, $2, "Tool calls" }
  $4 == "turn" { print $1, $2, "run" }
' > "$work/claims"

cut -f1,2 "$work/claims" | tr '\t' '\n' | sort -n -u > "$work/boundaries"

totals=$(awk -F '\t' -v claims_file="$work/claims" '
  function duration(seconds,   minutes) {
    minutes = int(seconds / 60)
    if (minutes < 60) return minutes "m"
    return int(minutes / 60) "h " minutes % 60 "m"
  }

  BEGIN {
    while ((getline line < claims_file) > 0) {
      split(line, field, "\t")
      claims++
      from[claims] = field[1] + 0
      to[claims] = field[2] + 0
      kind[claims] = field[3]
    }
  }

  { boundary[++boundaries] = $1 + 0 }

  END {
    if (claims == 0) exit
    for (index_ = 1; index_ < boundaries; index_++) {
      start = boundary[index_]
      finish = boundary[index_ + 1]
      sharing = 0
      running = 0
      for (claim = 1; claim <= claims; claim++) {
        if (from[claim] > start || to[claim] < finish) continue
        if (kind[claim] == "run") running = 1
        else share[++sharing] = kind[claim]
      }
      if (sharing == 0 && running) share[++sharing] = "Model time"
      for (shared = 1; shared <= sharing; shared++) spent[share[shared]] += (finish - start) / sharing
      if (sharing > 0) total += finish - start
    }
    printf "Total: %s\n", duration(total)
    printf "Waiting on the owner: %s\n", duration(spent["Waiting on the owner"])
    printf "Model time: %s\n", duration(spent["Model time"])
    printf "Tool calls: %s\n", duration(spent["Tool calls"])
    fflush()
    for (name in spent)
      if (name != "Waiting on the owner" && name != "Model time" && name != "Tool calls")
        printf "%s: %s\n", name, duration(spent[name]) | "sort"
    close("sort")
  }
' "$work/boundaries")

printf '## Time Spent\n\n'
printf '%s\n' "$totals" | sed 's/^/- /'
