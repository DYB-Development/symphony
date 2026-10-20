#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: test-inventory.sh <owner/repo> <pr-number> <draft.json> [--diff <file>]
       test-inventory.sh --titles <sha>

Lists every test a pull request adds or changes, with its title, file, line and
number of assertions, and writes the list beside the review draft. `--diff`
reads the pull request's diff from a file instead of fetching it from GitHub.
`--titles` prints the title of every test in the current repo at one revision.
See ~/.claude/rules/review-checks.md.
USAGE
  exit 64
}

is_test_file() {
  grep -q -E '(^|/)(test|tests|spec|__tests__)/|_test\.|_spec\.|\.test\.|\.spec\.' <<<"$1"
}

tests_in() {
  LC_ALL=C awk -v lines="$2" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    function title_of(s,   t, quote, closing) {
      if (match(s, /^[ \t]*(test|it|specify|scenario)[ (]+["'"'"'`]/)) {
        quote = substr(s, RSTART + RLENGTH - 1, 1)
        t = substr(s, RSTART + RLENGTH)
        closing = index(t, quote)
        if (closing) t = substr(t, 1, closing - 1)
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
      if (open && (touched || lines == "all")) print start "\t" last "\t" asserts "\t" title "\t" (touched ? touched : start)
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
        if (!touched && index(lines, "," NR ",")) touched = NR
        s = $0
        asserts += gsub(/(^|[^A-Za-z_])(assert|refute)[a-z_]*[ (]|(^|[^A-Za-z_])expect[ (]/, "", s)
      }
    }
    END { close_test(NR) }
  ' <<<"$1"
}

if [ "${1:-}" = "--titles" ]; then
  [ $# -eq 2 ] || usage
  git ls-tree -r --name-only "$2" | while IFS= read -r path; do
    is_test_file "$path" || continue
    tests_in "$(git show "$2:$path")" all | cut -f4
  done
  exit 0
fi

diff_file=""
if [ $# -eq 5 ] && [ "$4" = "--diff" ]; then
  diff_file=$5
elif [ $# -ne 3 ]; then
  usage
fi

repo=$1
pr=$2
draft=$3

result="${draft%.json}.tests.json"
rm -f "$result"

if [ -n "$diff_file" ]; then
  diff=$(cat "$diff_file")
else
  diff=$(gh pr diff "$pr" --repo "$repo")
fi
head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq '.headRefOid')

added=$(printf '%s\n' "$diff" | "$(dirname "$0")/diff-lines.sh" | awk -F'\t' '$1 == "RIGHT" { print $2 "\t" $3 }')

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

question='You are shown one test: its title and its body. Answer two questions about it.

Does the title name a behaviour, something the code does that a user or a caller could observe? A title such as "works" or "test 1" does not.

Does the body test that behaviour, so that it would fail if the code stopped doing what the title says?

Reply with exactly two lines and nothing else:
Title: names a behaviour   or   Title: does not name a behaviour
Body: tests that behaviour   or   Body: does not test that behaviour'

first_line_starting() {
  printf '%s\n' "$2" | grep -m1 "^$1" || true
}

verdict_on() {
  local reply title body
  reply=$(printf 'The title:\n\n%s\n\nThe body:\n\n%s\n' "$1" "$2" \
    | "$root/bin/ask-model.sh" test-inventory sonnet '.*' "$question") ||
    return 1
  title=$(first_line_starting 'Title:' "$reply")
  body=$(first_line_starting 'Body:' "$reply")
  case "$title" in
    'Title: names a behaviour') echo true ;;
    'Title: does not name a behaviour') echo false ;;
    *) echo "test-inventory.sh: the test-inventory reply has no Title line in either allowed form" >&2; return 1 ;;
  esac
  case "$body" in
    'Body: tests that behaviour') echo true ;;
    'Body: does not test that behaviour') echo false ;;
    *) echo "test-inventory.sh: the test-inventory reply has no Body line in either allowed form" >&2; return 1 ;;
  esac
}

tests='[]'
while IFS= read -r path; do
  is_test_file "$path" || continue
  lines=",$(printf '%s\n' "$added" | awk -F'\t' -v p="$path" '$1 == p { printf "%s,", $2 }')"
  content=$(gh api "repos/$repo/contents/$path?ref=$head" -H 'Accept: application/vnd.github.raw' 2>/dev/null) ||
    { echo "test-inventory.sh: $path could not be read, so its tests are unread" >&2; exit 70; }
  while IFS=$'\t' read -r start finish asserts title touched; do
    [ -n "$start" ] || continue
    body=$(printf '%s\n' "$content" | sed -n "${start},${finish}p")
    verdict=$(verdict_on "$title" "$body") || exit 70
    tests=$(jq -c --arg path "$path" --argjson line "$touched" --argjson assertions "$asserts" --arg title "$title" \
      --argjson names "$(sed -n 1p <<<"$verdict")" --argjson tests_it "$(sed -n 2p <<<"$verdict")" \
      '. + [{path: $path, line: $line, title: $title, assertions: $assertions,
             tests_more_than_one_thing: ($assertions > 1),
             title_names_a_behaviour: $names, body_tests_that_behaviour: $tests_it}]' <<<"$tests")
  done < <(tests_in "$content" "$lines")
done < <(printf '%s\n' "$added" | cut -f1 | sort -u)

jq -n --argjson tests "$tests" '{tests: $tests, hits: [$tests[] | . as $t | (
    (select($t.title_names_a_behaviour | not) | {pattern: "test-title-names-no-behaviour",
      reason: "The title \"\($t.title)\" names no behaviour, so a failure does not say what broke.",
      fix: "Rename the test after the one behaviour it checks."}),
    (select($t.title_names_a_behaviour and ($t.body_tests_that_behaviour | not)) | {pattern: "test-body-misses-its-title",
      reason: "The body does not test what the title \"\($t.title)\" says, so it can pass while that behaviour is broken.",
      fix: "Assert on the behaviour the title names, or rename the test after what it asserts."}),
    (select($t.tests_more_than_one_thing) | {pattern: "test-asserts-more-than-one-thing",
      reason: "The test makes \($t.assertions) assertions, so one failure hides whether the others still hold.",
      fix: "Split it into one test per assertion."})
  ) | {path: $t.path, line: $t.line, check: "Tests", source: "tests"} + .]}' > "$result"
