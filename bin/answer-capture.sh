#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: answer-capture.sh record < hook.json

Records each question the owner was asked, with the answer, into that repo's
review list, where the owner approves it before it settles later questions.
See ~/.claude/rules/saved-answers.md.
USAGE
  exit 64
}

[ "${1:-}" = record ] || usage

repo_answers_dir=${SYMPHONY_REPO_ANSWERS_DIR:-"$HOME/.config/symphony/answers"}

payload=$(cat)
common=$(git -C "$(printf '%s' "$payload" | jq -r '.cwd // "."')" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
repo=$(basename "$(dirname "$common")")

review="$repo_answers_dir/$repo.review.json"
mkdir -p "$repo_answers_dir"
[ -f "$review" ] || printf '%s\n' '{"version": 1, "entries": []}' > "$review"

printf '%s' "$payload" | jq --arg date "$(date +%F)" --slurpfile list "$review" '
  (.tool_response.answers // {}) as $answers |
  .tool_input.questions as $questions |
  $list[0] | .entries += [$questions[] | {
    question,
    answer: ($answers[.question] // ""),
    notes: "",
    date: $date,
    status: "answered"
  }]' > "$review.tmp"
mv "$review.tmp" "$review"
