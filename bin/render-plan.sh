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
