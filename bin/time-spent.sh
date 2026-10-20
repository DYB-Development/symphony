#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh --spans | time-spent.sh --render

Prints the PR body's Time Spent section from the spans `usage.sh --spans`
prints on standard input: the total, then one line per kind of work. It says
`Not measured.` when no span names this branch.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

[ "${1:-}" = "--render" ] || usage

work=$(mktemp -d "${TMPDIR:-/tmp}/time-spent.XXXXXX")
trap 'rm -rf "$work"' EXIT

awk -F '\t' -v idle_cap=600 '
  BEGIN { OFS = "\t" }
  $4 == "tool" && $5 ~ /-scribe$/ { print $1, $2, $5; next }
  $4 == "tool" && $6 == "Agent" && $7 ~ /-scribe$/ { print $1, $2, $7; next }
  $4 == "tool" && $6 == "Agent" { print $1, $2, "run"; next }
  $4 == "tool" { print $1, $2, "Tool calls" }
  $4 == "turn" { print $1, $2, "run" }
  $4 == "wait" { print $1, ($2 - $1 < idle_cap ? $2 : $1 + idle_cap), "Waiting on the owner" }
' > "$work/claims"

cut -f1,2 "$work/claims" | tr '\t' '\n' | sort -n -u > "$work/boundaries"

totals=$(awk -F '\t' -v claims_file="$work/claims" '
  function duration(minutes) {
    if (minutes < 60) return minutes "m"
    return int(minutes / 60) "h " minutes % 60 "m"
  }

  function apportion(   name, counted, largest, picked) {
    counted = 0
    for (name in spent) {
      minutes[name] = int(spent[name] / 60)
      counted += minutes[name]
    }
    for (; counted < int(total / 60); counted++) {
      largest = -1
      for (name in spent)
        if (!(name in rounded_up) && spent[name] - minutes[name] * 60 > largest) {
          largest = spent[name] - minutes[name] * 60
          picked = name
        }
      minutes[picked]++
      rounded_up[picked] = 1
    }
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
    spent["Waiting on the owner"] += 0
    spent["Model time"] += 0
    spent["Tool calls"] += 0
    apportion()
    printf "Total: %s\n", duration(int(total / 60))
    printf "Waiting on the owner: %s\n", duration(minutes["Waiting on the owner"])
    printf "Model time: %s\n", duration(minutes["Model time"])
    printf "Tool calls: %s\n", duration(minutes["Tool calls"])
    fflush()
    for (name in spent)
      if (name != "Waiting on the owner" && name != "Model time" && name != "Tool calls")
        printf "%s: %s\n", name, duration(minutes[name]) | "sort"
    close("sort")
  }
' "$work/boundaries")

printf '## Time Spent\n\n'
if [ -n "$totals" ]; then
  printf '%s\n' "$totals" | sed 's/^/- /'
else
  printf 'Not measured.\n'
fi
