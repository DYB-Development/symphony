#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: commit-shape.sh <owner/repo> <pr-number> <draft.json>

Reads each commit of a pull request and flags the ones that do not hold both a
test file and a code file, and writes every commit's result beside the review
draft.
See ~/.claude/rules/review-checks.md.
USAGE
  exit 64
}

[ $# -eq 3 ] || usage

repo=$1
pr=$2
draft=$3

result="${draft%.json}.commits.json"

is_test_file() {
  grep -q -E '(^|/)(test|tests|spec|__tests__)/|_test\.|_spec\.|\.test\.|\.spec\.' <<<"$1"
}

is_doc_file() {
  grep -q -E '(^|/)docs?/|\.(md|markdown|txt|rst|adoc)$' <<<"$1"
}

commits='[]'
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  tests=0
  code=0
  docs=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if is_test_file "$file"; then tests=$((tests + 1))
    elif is_doc_file "$file"; then docs=$((docs + 1))
    else code=$((code + 1)); fi
  done < <(gh api "repos/$repo/commits/$sha" --jq '.files[].filename')

  if [ "$tests" -gt 0 ] && [ "$code" -gt 0 ]; then shape="test-and-code"
  elif [ "$docs" -gt 0 ] && [ "$tests" -eq 0 ] && [ "$code" -eq 0 ]; then shape="docs-only"
  else shape=flagged; fi

  commits=$(jq -c --arg sha "$sha" --arg shape "$shape" '. + [{sha: $sha, shape: $shape}]' <<<"$commits")
done < <(gh api "repos/$repo/pulls/$pr/commits" --paginate --jq '.[].sha')

jq -n --argjson commits "$commits" '{commits: $commits}' > "$result"
