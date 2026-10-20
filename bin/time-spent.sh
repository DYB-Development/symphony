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

here="$(dirname "$0")"
kinds="${TIME_KINDS_FILE:-$here/../rules/time-kinds.tsv}"

work=$(mktemp -d "${TMPDIR:-/tmp}/time-spent.XXXXXX")
trap 'rm -rf "$work"' EXIT

awk -F '\t' -v idle_cap=600 -v kinds_file="$kinds" '
  function kind_of(tool, command,   pattern) {
    for (pattern = 1; pattern <= patterns; pattern++)
      if (tool ~ tool_pattern[pattern] && command ~ command_pattern[pattern]) return kind[pattern]
    return "Other tool calls"
  }

  BEGIN {
    OFS = "\t"
    getline line < kinds_file
    while ((getline line < kinds_file) > 0) {
      split(line, field, "\t")
      patterns++
      kind[patterns] = field[1]
      tool_pattern[patterns] = field[2]
      command_pattern[patterns] = field[3]
    }
  }
  $4 == "tool" && $5 ~ /-scribe$/ && $7 ~ /read-draft\.sh/ { print $1, $2, "Draft-reader rounds", $5; next }
  $4 == "tool" && $5 ~ /-scribe$/ { print $1, $2, $5, $5; next }
  $4 == "tool" && $6 == "Agent" && $7 ~ /-scribe$/ { print $1, $2, $7, $7, "run"; next }
  $4 == "tool" && $6 == "Agent" { print $1, $2, "run"; next }
  $4 == "tool" { print $1, $2, kind_of($6, $7) }
  $4 == "turn" { print $1, $2, "run" }
  $4 == "wait" { print $1, ($2 - $1 < idle_cap ? $2 : $1 + idle_cap), "Waiting on the owner" }
' > "$work/claims"

cut -f1,2 "$work/claims" | tr '\t' '\n' | sort -n -u > "$work/boundaries"

totals=$(awk -F '\t' -v claims_file="$work/claims" -v kinds_file="$kinds" '
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
    getline line < kinds_file
    while ((getline line < kinds_file) > 0) {
      split(line, field, "\t")
      if (!(field[1] in listed)) order[++listed_kinds] = field[1]
      listed[field[1]] = 1
    }
    order[++listed_kinds] = "Other tool calls"
    listed["Waiting on the owner"] = listed["Model time"] = listed["Other tool calls"] = 1
    while ((getline line < claims_file) > 0) {
      split(line, field, "\t")
      claims++
      from[claims] = field[1] + 0
      to[claims] = field[2] + 0
      kind[claims] = field[3]
      owner[claims] = field[4]
      container[claims] = field[5] == "run"
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
      split("", covered)
      split("", held)
      for (claim = 1; claim <= claims; claim++) {
        if (from[claim] > start || to[claim] < finish) continue
        if (kind[claim] == "run") running = 1
        else if (container[claim]) held[owner[claim]] = kind[claim]
        else {
          share[++sharing] = kind[claim]
          if (owner[claim] != "") covered[owner[claim]] = 1
        }
      }
      for (run in held)
        if (!(run in covered)) share[++sharing] = held[run]
      if (sharing == 0 && running) share[++sharing] = "Model time"
      for (shared = 1; shared <= sharing; shared++) spent[share[shared]] += (finish - start) / sharing
      if (sharing > 0) total += finish - start
    }
    for (name in listed) spent[name] += 0
    apportion()
    printf "Total: %s\n", duration(int(total / 60))
    printf "Waiting on the owner: %s\n", duration(minutes["Waiting on the owner"])
    printf "Model time: %s\n", duration(minutes["Model time"])
    for (index_ = 1; index_ <= listed_kinds; index_++)
      printf "%s: %s\n", order[index_], duration(minutes[order[index_]])
    fflush()
    for (name in spent)
      if (!(name in listed))
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
