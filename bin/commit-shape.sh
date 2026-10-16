#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: commit-shape.sh <owner/repo> <pr-number> <draft.json>
       commit-shape.sh --render <commits.json>

Reads each commit of a pull request and flags the ones that do not hold both a
test file and a code file, and writes every commit's result beside the review
draft. `--render` prints the Commits bullet of the review summary from that
result.
See ~/.claude/rules/review-checks.md.
USAGE
  exit 64
}

if [ "${1:-}" = "--render" ]; then
  [ $# -eq 2 ] || usage
  jq -r '[.commits[] | select(.exception == "neither")] as $bare
    | if ($bare | length) == 0 then "- ✅ **Commits** — nothing found"
      else "- ❌ **Commits** — \(if ($bare | length) == 1 then "one commit changes" else "\($bare | length) commits change" end) code with no test.",
        ($bare[] | "  - `\(.sha[0:7])` \(.subject) — It changes code in \(.code_files | join(", ")) and holds no test. Add the test that drives this change.")
      end' "$2"
  exit 0
fi

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

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model="$("$root/bin/agent-model.sh" lookup commit-shape sonnet)"

question='A commit should hold a test and the code it drives. You are shown one commit that does not. Decide which of these it is:

- interface: it adds or changes an interface across several files, such as a route, a controller and a view, and the test that drives it sits in a neighbouring commit.
- refactor: it rearranges code and changes no behaviour anyone can see or call.
- neither: it adds or changes behaviour without a test.

Reply with one line and nothing else: Exception: interface, Exception: refactor or Exception: neither.'

exception_of() {
  local reply
  reply=$({
    printf 'The commit message:\n\n'
    gh api "repos/$repo/commits/$1" --jq '.commit.message'
    printf '\nThe commit diff:\n\n'
    gh api "repos/$repo/commits/$1" -H 'Accept: application/vnd.github.diff'
  } | claude -p --model "$model" --system-prompt "$question" --tools "" --setting-sources "" \
      --no-session-persistence --strict-mcp-config) ||
    { echo "commit-shape.sh: the question about commit $1 failed" >&2; exit 70; }
  printf '%s\n' "$reply" | awk 'NF { last = $0 } END { print last }' \
    | sed -n -E 's/^Exception: (interface|refactor|neither)$/\1/p'
}

commits='[]'
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  tests=0
  code=0
  docs=0
  code_files='[]'
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if is_test_file "$file"; then tests=$((tests + 1))
    elif is_doc_file "$file"; then docs=$((docs + 1))
    else
      code=$((code + 1))
      code_files=$(jq -c --arg file "$file" '. + [$file]' <<<"$code_files")
    fi
  done < <(gh api "repos/$repo/commits/$sha" --jq '.files[].filename')
  subject=$(gh api "repos/$repo/commits/$sha" --jq '.commit.message' | head -1)

  if [ "$tests" -gt 0 ] && [ "$code" -gt 0 ]; then shape="test-and-code"
  elif [ "$docs" -gt 0 ] && [ "$tests" -eq 0 ] && [ "$code" -eq 0 ]; then shape="docs-only"
  else shape=flagged; fi

  exception=""
  if [ "$shape" = flagged ]; then exception=$(exception_of "$sha") || exit 70; fi

  commits=$(jq -c --arg sha "$sha" --arg subject "$subject" --argjson code_files "$code_files" \
    --arg shape "$shape" --arg exception "$exception" \
    '. + [{sha: $sha, subject: $subject, code_files: $code_files, shape: $shape,
           exception: (if $exception == "" then null else $exception end)}]' <<<"$commits")
done < <(gh api "repos/$repo/pulls/$pr/commits" --paginate --jq '.[].sha')

jq -n --argjson commits "$commits" '{commits: $commits}' > "$result"
