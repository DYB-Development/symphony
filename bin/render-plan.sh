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
root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fonts='https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Schibsted+Grotesk:wght@500;600;700&family=Source+Sans+3:wght@400;600;700&display=swap'
esc_awk='function esc(t) { gsub(/&/, "\\&amp;", t); gsub(/</, "\\&lt;", t); gsub(/>/, "\\&gt;", t); return t }'

escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

header_facts() {
  awk "$esc_awk"'
    /^## 01 / { exit }
    match($0, /^(Scope|Shape|Status|Date)  +/) {
      printf "<div><dt>%s</dt><dd>%s</dd></div>", $1, esc(substr($0, RLENGTH + 1))
    }'
}

mark_structure() {
  awk -v work="$1" "$esc_awk"'
    function mark(html,   id) {
      id = sprintf("MARKER-%04d-END", ++marks)
      printf "%s", html > (work "/" id)
      close(work "/" id)
      printf "\n%s\n\n", id
    }
    function close_unit(   h) { h = unit ? "</article>" : ""; unit = 0; return h }
    function close_stage(   h) { h = close_unit() (stage ? "</section>" : ""); stage = 0; return h }
    function close_part(   h) { h = close_stage() (part ? "</section>" : ""); part = 0; return h }
    function close_contents_part(   h) {
      h = (contents_units ? "</ol>" : "") (contents_part ? "</li>" : "")
      contents_units = 0
      contents_part = 0
      return h
    }
    function open_part(num, label) {
      mark(close_part() "<section class=\"part\" aria-labelledby=\"s" num "\"><h2 id=\"s" num "\"><span class=\"num\">" num "</span> " esc(label) "</h2>")
      contents = contents close_contents_part() "<li><a href=\"#s" num "\"><span class=\"num\">" num "</span> " esc(label) "</a>"
      contents_part = 1
      part = num
    }
    function open_stage(n, name) {
      mark(close_stage() "<section class=\"stage\" data-stage=\"" n "\"><h3 id=\"stage-" n "\">" esc(name) "</h3>")
      contents = contents (contents_units ? "" : "<ol class=\"toc-units\">") "<li class=\"toc-stage\"><a href=\"#stage-" n "\">" esc(name) "</a></li>"
      contents_units = 1
      stage = n
    }
    function open_unit(rest,   number, id, heading, entry) {
      number = substr(rest, 1, index(rest, " ") - 1)
      id = number
      gsub(/\./, "-", id)
      heading = substr(rest, index(rest, " ") + 1)
      entry = heading
      sub(/^— /, "", entry)
      mark(close_unit() "<article class=\"unit\" data-stage=\"" stage "\"><h4 id=\"unit-" id "\"><span class=\"unum\">Unit " number "</span> <span class=\"utitle\">" esc(heading) "</span></h4>")
      contents = contents "<li><a href=\"#unit-" id "\"><span class=\"unum\">" number "</span> " esc(entry) "</a></li>"
      unit = 1
    }
    function open_stamp() {
      mark(close_part() "<footer class=\"stamp\"><h2 id=\"stamp\">Generation Metadata</h2>")
      stamp = 1
    }

    in_diagram && /^```$/ {
      mark("<figure class=\"diagram\"><pre class=\"mermaid\">" esc(diagram) "</pre></figure>")
      in_diagram = 0
      next
    }
    in_diagram { diagram = diagram (diagram == "" ? "" : "\n") $0; next }

    rule_held && /^$/ { next }
    rule_held && /^## Generation Metadata$/ { rule_held = 0; open_stamp(); next }
    rule_held { print "---"; print ""; rule_held = 0 }
    part && /^---$/ { rule_held = 1; next }

    /^## (0[1-9]|10) / { open_part(substr($0, 4, 2), substr($0, 7)); next }
    part == "09" && /^### Stage [1-4] / { open_stage(substr($0, 11, 1), substr($0, 5)); next }
    stage && /^#### Unit [1-4]\.[0-9]+ / { open_unit(substr($0, 11)); next }
    unit && /^## / { print "##### " substr($0, 4); next }
    part && /^```mermaid$/ { in_diagram = 1; diagram = ""; next }
    !part && !stamp { next }
    { print }

    END {
      mark(close_part() (stamp ? "</footer>" : ""))
      printf "<aside aria-label=\"Contents\"><p class=\"label\">Contents</p><ol class=\"toc\">%s</ol></aside>\n", contents close_contents_part() > (work "/contents.html")
    }'
}

fill_structure() {
  awk -v work="$1" '
    /^(<p>)?MARKER-[0-9]+-END(<\/p>)?$/ {
      id = $0
      gsub(/<\/?p>/, "", id)
      while ((getline line < (work "/" id)) > 0) print line
      close(work "/" id)
      next
    }
    {
      gsub(/<markdown-accessiblity-table>/, "<div class=\"table-wrap\">")
      gsub(/<\/markdown-accessiblity-table>/, "</div>")
      gsub(/ class="notranslate"/, "")
      print
    }'
}

issue="$(gh issue view "$number" --repo "$repo" --json title,body)" ||
  { echo "render-plan.sh: could not read issue $repo#$number" >&2; exit 70; }
title="$(printf '%s' "$issue" | jq -r .title | escape)"
body="$(printf '%s' "$issue" | jq -r .body)"

work="$(mktemp -d "${TMPDIR:-/tmp}/render-plan.XXXXXX")"
trap 'rm -rf "$work"' EXIT

printf '%s\n' "$body" | mark_structure "$work" > "$work/plan.md"
gh api markdown -f mode=gfm -F text=@"$work/plan.md" > "$work/plan.html" ||
  { echo "render-plan.sh: GitHub could not render the plan's markdown" >&2; exit 70; }

printf '<title>%s</title>\n' "$title"
printf '<link rel="stylesheet" href="%s">\n' "$fonts"
printf '<style>%s</style>\n' "$(cat "$root/templates/plan-page.css")"
printf '<div class="shell">\n'
cat "$work/contents.html"
printf '<main>\n'
printf '<header class="masthead"><p class="kicker">Feature plan · %s#%s</p><h1>%s</h1>' "$repo" "$number" "$title"
printf '<dl class="facts">%s</dl>\n</header>\n' "$(printf '%s\n' "$body" | header_facts)"
fill_structure "$work" < "$work/plan.html"
printf '</main>\n</div>\n'
