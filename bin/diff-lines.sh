#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: diff-lines.sh < pull-request.diff

Prints every line a unified diff adds or removes, one per row, as the side, the
path, the line number and the line's text, separated by tabs. An added line is
on the RIGHT side and numbered in the new file, and a removed line is on the
LEFT side and numbered in the old one. A path git wrote in quotes with escapes
is printed as the file is named.
USAGE
  exit 64
}

[ $# -eq 0 ] || usage

awk '
  function path_of(line,   p, out, i, c, oct) {
    p = substr(line, 5)
    sub(/\t.*$/, "", p)
    if (p ~ /^".*"$/) {
      p = substr(p, 2, length(p) - 2)
      out = ""
      for (i = 1; i <= length(p); i++) {
        c = substr(p, i, 1)
        if (c == "\\" && substr(p, i + 1, 1) ~ /[0-7]/) {
          oct = substr(p, i + 1, 3)
          out = out sprintf("%c", (substr(oct, 1, 1) * 64) + (substr(oct, 2, 1) * 8) + substr(oct, 3, 1))
          i += 3
        } else if (c == "\\") {
          out = out substr(p, i + 1, 1)
          i++
        } else {
          out = out c
        }
      }
      p = out
    }
    sub(/^[ab]\//, "", p)
    return p
  }
  /^diff --git / { in_hunk = 0; next }
  !in_hunk && /^index / { next }
  !in_hunk && /^--- / { old_path = path_of($0); next }
  !in_hunk && /^\+\+\+ / { new_path = path_of($0); next }
  /^@@ / {
    split($2, o, ","); old = o[1] + 0; if (old < 0) old = -old
    split($3, n, ","); new = n[1] + 0; if (new < 0) new = -new
    in_hunk = 1
    next
  }
  !in_hunk { next }
  /^\\/ { next }
  /^-/ { print "LEFT\t" old_path "\t" old "\t" substr($0, 2); old++; next }
  /^\+/ { print "RIGHT\t" new_path "\t" new "\t" substr($0, 2); new++; next }
  { old++; new++ }
'
