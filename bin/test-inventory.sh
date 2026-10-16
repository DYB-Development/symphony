#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: test-inventory.sh <owner/repo> <pr-number> <draft.json>

Lists every test a pull request adds or changes, with its title, file, line and
number of assertions, and writes the list beside the review draft.
See ~/.claude/rules/review-checks.md.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage

repo=$1
pr=$2
draft=$3

result="${draft%.json}.tests.json"

diff=$(gh pr diff "$pr" --repo "$repo")
head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq '.headRefOid')

added=$(printf '%s\n' "$diff" | awk '
  /^diff --git / { in_hunk = 0; next }
  !in_hunk && /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
  /^@@ / { split($3, n, ","); line = n[1] + 0; if (line < 0) line = -line; in_hunk = 1; next }
  !in_hunk { next }
  /^\\/ { next }
  /^-/ { next }
  /^\+/ { print path "\t" line; line++; next }
  { line++ }
')

is_test_file() {
  grep -q -E '(^|/)(test|tests|spec|__tests__)/|_test\.|_spec\.|\.test\.|\.spec\.' <<<"$1"
}

tests_in() {
  awk -v lines="$2" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    function title_of(s,   t) {
      if (match(s, /^[ \t]*(test|it|specify|scenario)[ (]+["'"'"'`]/)) {
        t = substr(s, RSTART + RLENGTH)
        sub(/["'"'"'`].*$/, "", t)
        return t
      }
      if (match(s, /^[ \t]*def test_[A-Za-z0-9_]+/)) {
        t = substr(s, RSTART, RLENGTH)
        sub(/^[ \t]*def test_/, "", t)
        gsub(/_/, " ", t)
        return t
      }
      return ""
    }
    function close_test(last) {
      if (open && touched) print start "\t" last "\t" asserts "\t" title
      open = 0
    }
    {
      if (open && NF && indent_of($0) <= depth) { close_test(NR) ; next }
      t = title_of($0)
      if (t != "") {
        close_test(NR - 1)
        open = 1; start = NR; depth = indent_of($0); title = t; asserts = 0; touched = 0
      }
      if (open) {
        if (index(lines, "," NR ",")) touched = 1
        s = $0
        asserts += gsub(/(^|[^A-Za-z_])(assert|refute)[a-z_]*[ (]|(^|[^A-Za-z_])expect[ (]/, "", s)
      }
    }
    END { close_test(NR) }
  ' <<<"$1"
}

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model="$("$root/bin/agent-model.sh" lookup test-inventory sonnet)"

question='You are shown one test: its title and its body. Answer two questions about it.

Does the title name a behaviour, something the code does that a user or a caller could observe? A title such as "works" or "test 1" does not.

Does the body test that behaviour, so that it would fail if the code stopped doing what the title says?

Reply with exactly two lines and nothing else:
Title: names a behaviour   or   Title: does not name a behaviour
Body: tests that behaviour   or   Body: does not test that behaviour'

verdict_on() {
  local reply
  reply=$(printf 'The title:\n\n%s\n\nThe body:\n\n%s\n' "$1" "$2" \
    | claude -p --model "$model" --system-prompt "$question" --tools "" --setting-sources "" \
        --no-session-persistence --strict-mcp-config) ||
    { echo "test-inventory.sh: the question about the test \"$1\" failed" >&2; return 1; }
  printf '%s\n' "$reply" | sed -n -E 's/^Title: (names|does not name) a behaviour$/\1/p' \
    | sed 's/^names$/true/; s/^does not name$/false/'
  printf '%s\n' "$reply" | sed -n -E 's/^Body: (tests|does not test) that behaviour$/\1/p' \
    | sed 's/^tests$/true/; s/^does not test$/false/'
}

tests='[]'
while IFS= read -r path; do
  is_test_file "$path" || continue
  lines=",$(printf '%s\n' "$added" | awk -F'\t' -v p="$path" '$1 == p { printf "%s,", $2 }')"
  content=$(gh api "repos/$repo/contents/$path?ref=$head" -H 'Accept: application/vnd.github.raw')
  while IFS=$'\t' read -r start finish asserts title; do
    [ -n "$start" ] || continue
    body=$(printf '%s\n' "$content" | sed -n "${start},${finish}p")
    verdict=$(verdict_on "$title" "$body") || exit 70
    tests=$(jq -c --arg path "$path" --argjson line "$start" --argjson assertions "$asserts" --arg title "$title" \
      --argjson names "$(sed -n 1p <<<"$verdict")" --argjson tests_it "$(sed -n 2p <<<"$verdict")" \
      '. + [{path: $path, line: $line, title: $title, assertions: $assertions,
             tests_more_than_one_thing: ($assertions > 1),
             title_names_a_behaviour: $names, body_tests_that_behaviour: $tests_it}]' <<<"$tests")
  done < <(tests_in "$content" "$lines")
done < <(printf '%s\n' "$added" | cut -f1 | sort -u)

jq -n --argjson tests "$tests" '{tests: $tests}' > "$result"
