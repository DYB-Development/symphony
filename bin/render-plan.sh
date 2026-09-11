#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: render-plan.sh <owner/repo> <issue-number>

Prints the page for a feature plan, built from the plan issue's title and body
in the one layout every plan page uses.
See ~/.claude/rules/feature-plan.md.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

repo=$1
number=$2

issue="$(gh issue view "$number" --repo "$repo" --json title,body)" ||
  { echo "render-plan.sh: could not read issue $repo#$number" >&2; exit 70; }

escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

title="$(printf '%s' "$issue" | jq -r .title)"

printf '<title>%s</title>\n' "$(printf '%s' "$title" | escape)"

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Schibsted+Grotesk:wght@500;600;700&family=Source+Sans+3:wght@400;600;700&display=swap">\n'
printf '<style>%s</style>\n' "$(cat "$root/templates/plan-page.css")"

printf '<header class="masthead"><p class="kicker">Feature plan · %s#%s</p><h1>%s</h1>' \
  "$repo" "$number" "$(printf '%s' "$title" | escape)"

body="$(printf '%s' "$issue" | jq -r .body)"

esc_awk='function esc(t) { gsub(/&/, "\\&amp;", t); gsub(/</, "\\&lt;", t); gsub(/>/, "\\&gt;", t); return t }'

printf '<dl class="facts">%s</dl>\n</header>\n' "$(printf '%s\n' "$body" | awk "$esc_awk"'
  /^## 01 / { exit }
  match($0, /^(Scope|Shape|Status|Date)  +/) {
    printf "<div><dt>%s</dt><dd>%s</dd></div>", $1, esc(substr($0, RLENGTH + 1))
  }')"

work="$(mktemp -d "${TMPDIR:-/tmp}/render-plan.XXXXXX")"
trap 'rm -rf "$work"' EXIT

printf '%s\n' "$body" | awk -v work="$work" "$esc_awk"'
  function mark(html,   id) {
    id = sprintf("MARKER-%04d-END", ++marks)
    printf "%s", html > (work "/" id)
    close(work "/" id)
    printf "\n%s\n\n", id
  }
  function close_stage(   h) {
    h = stage ? "</section>" : ""
    stage = 0
    return h
  }
  function close_part(   h) {
    h = close_stage() (part ? "</section>" : "")
    part = 0
    return h
  }

  match($0, /^## (0[1-9]|10) /) {
    num = substr($0, 4, 2)
    mark(close_part() "<section class=\"part\" aria-labelledby=\"s" num "\"><h2 id=\"s" num "\"><span class=\"num\">" num "</span> " esc(substr($0, 7)) "</h2>")
    part = num
    next
  }
  part == "09" && match($0, /^### Stage [1-4] /) {
    n = substr($0, 11, 1)
    mark(close_stage() "<section class=\"stage\" data-stage=\"" n "\"><h3 id=\"stage-" n "\">" esc(substr($0, 5)) "</h3>")
    stage = n
    next
  }

  !part { next }
  { print }
  END { mark(close_part()) }
' > "$work/plan.md"

gh api markdown -f mode=gfm -F text=@"$work/plan.md" > "$work/plan.html" ||
  { echo "render-plan.sh: GitHub could not render the plan's markdown" >&2; exit 70; }

awk -v work="$work" '
  match($0, /^(<p>)?MARKER-[0-9]+-END(<\/p>)?$/) {
    id = $0
    gsub(/<\/?p>/, "", id)
    while ((getline line < (work "/" id)) > 0) print line
    close(work "/" id)
    next
  }
  { print }
' "$work/plan.html"
