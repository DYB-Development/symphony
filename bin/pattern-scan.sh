#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pattern-scan.sh <owner/repo> <pr-number> <draft.json>

Matches every line a pull request adds against the patterns in the packs under
rules/patterns, and writes each hit beside the review draft.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage

repo=$1
pr=$2
draft=$3

packs_dir=${SYMPHONY_PATTERNS_DIR:-"$(cd "$(dirname "$0")/.." && pwd)/rules/patterns"}
result="${draft%.json}.scan.json"

diff=$(gh pr diff "$pr" --repo "$repo")

added=$(printf '%s\n' "$diff" | awk '
  /^diff --git / { in_hunk = 0; next }
  !in_hunk && /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
  /^@@ / { split($3, n, ","); line = n[1] + 0; if (line < 0) line = -line; in_hunk = 1; next }
  !in_hunk { next }
  /^\\/ { next }
  /^-/ { next }
  /^\+/ { print path "\t" line "\t" substr($0, 2); line++; next }
  { line++ }
')

unsaid=$(jq -r -n 'inputs | (input_filename | split("/") | last | rtrimstr(".json")) as $pack
  | select(.applies != "always" and ((.applies | type) != "object"
      or (.applies | keys) != ["framework"] and (.applies | keys) != ["library"]))
  | "pattern-scan.sh: pack \($pack) does not say whether it applies always, to a framework or to a library"' \
  "$packs_dir"/*.json)
[ -z "$unsaid" ] || { printf '%s\n' "$unsaid" >&2; exit 65; }

head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq '.headRefOid')

file_at_head() {
  gh api "repos/$repo/contents/$1?ref=$head" -H 'Accept: application/vnd.github.raw' 2>/dev/null || true
}

gemfile_lock=$(file_at_head Gemfile.lock)
package_json=$(file_at_head package.json)

file_showing_dependency() {
  if grep -q -E "^    $1 \(" <<<"$gemfile_lock"; then
    printf 'Gemfile.lock'
  elif jq -e --arg name "$1" '[.dependencies, .devDependencies] | any(has($name)?)' \
      <<<"$package_json" >/dev/null 2>&1; then
    printf 'package.json'
  fi
}

applied='[]'
for pack_file in "$packs_dir"/*.json; do
  pack=$(basename "$pack_file" .json)
  dependency=$(jq -r '.applies | if type == "object" then .framework // .library else "" end' "$pack_file")
  if [ -z "$dependency" ]; then
    shown_by=""
  else
    shown_by=$(file_showing_dependency "$dependency")
    [ -n "$shown_by" ] || continue
  fi
  applied=$(jq -c --arg pack "$pack" --arg shown_by "$shown_by" \
    '. + [{pack: $pack, shown_by: (if $shown_by == "" then null else $shown_by end)}]' <<<"$applied")
done

patterns=$(jq -c -n --argjson applied "$applied" '[inputs
  | (input_filename | split("/") | last | rtrimstr(".json")) as $pack
  | select(any($applied[]; .pack == $pack))
  | .patterns[] | . + {pack: $pack}]' "$packs_dir"/*.json)

incomplete=$(jq -r '.[] | . as $p | ["check", "reason", "fix"][]
  | select(($p[.] // "") == "") | "pattern-scan.sh: \($p.pack) pattern \($p.name) has no \(.)"' <<<"$patterns")
[ -z "$incomplete" ] || { printf '%s\n' "$incomplete" >&2; exit 65; }

marked_names() {
  printf '%s' "$1" | grep -o -E 'symphony-allow: [A-Za-z0-9_-]+' | sed 's/^symphony-allow: //' || true
}

hits='[]'
skipped='[]'
while IFS= read -r pattern; do
  regex=$(jq -r '.regex' <<<"$pattern")
  name=$(jq -r '.name' <<<"$pattern")
  matches=$(printf '%s\n' "$added" | cut -f3- | grep -n -E -e "$regex" | cut -d: -f1 || true)
  for index in $matches; do
    row=$(printf '%s\n' "$added" | sed -n "${index}p")
    if marked_names "$row" | grep -qxF -- "$name"; then
      skipped=$(jq -c --arg path "$(printf '%s' "$row" | cut -f1)" --argjson line "$(printf '%s' "$row" | cut -f2)" \
        --arg pattern "$name" '. + [{path: $path, line: $line, pattern: $pattern}]' <<<"$skipped")
      continue
    fi
    hits=$(jq -c --arg path "$(printf '%s' "$row" | cut -f1)" --argjson line "$(printf '%s' "$row" | cut -f2)" \
      --argjson pattern "$pattern" \
      '. + [{path: $path, line: $line, pattern: $pattern.name, check: $pattern.check,
             reason: $pattern.reason, fix: $pattern.fix}]' <<<"$hits")
  done
done < <(printf '%s\n' "$patterns" | jq -c '.[]')

known_names=$(jq -r '.[].name' <<<"$patterns")

while IFS=$'\t' read -r path line text; do
  names=$(marked_names "$text")
  if [ -n "$names" ] && ! grep -vxF -f <(printf '%s\n' "$known_names") <<<"$names" >/dev/null; then
    continue
  fi
  hits=$(jq -c --arg path "$path" --argjson line "$line" '. + [{path: $path, line: $line,
      pattern: "unknown-false-hit-marker", check: "Patterns",
      reason: "A false-hit marker that names no pattern of the packs applied here excuses nothing, so it reads as an exemption that does not exist.",
      fix: "Name the pattern the line is excused from, or remove the marker."}]' <<<"$hits")
done < <(printf '%s\n' "$added" | awk -F'\t' '$3 ~ /symphony-allow:/')

jq -n --argjson hits "$hits" --argjson skipped "$skipped" --argjson patterns "$patterns" --argjson applied "$applied" \
  '{hits: $hits, skipped: $skipped, applied: $applied, patterns: [$patterns[] | {pack, name, check}]}' > "$result"
