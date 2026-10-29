#!/usr/bin/env bash
set -euo pipefail

repo_answers_dir=${SYMPHONY_REPO_ANSWERS_DIR:-"$HOME/.config/symphony/answers"}

common=$(git rev-parse --path-format=absolute --git-common-dir)
repo=$(basename "$(dirname "$common")")
review="$repo_answers_dir/$repo.review.json"
answers="$repo_answers_dir/$repo.json"

remove_first() {
  jq '.entries |= .[1:]' "$review" > "$review.tmp"
  mv "$review.tmp" "$review"
}

[ -f "$answers" ] || printf '%s\n' '{"version": 1, "answers": []}' > "$answers"

entry=$(jq -c '.entries[0]' "$review")
wording=$(jq -r '.answer' <<< "$entry")
while read -r choice; do
  case "$choice" in
    a)
      read -r name
      jq --arg name "$name" --arg answer "$wording" --argjson entry "$entry" \
        '.answers += [{name: $name, question: $entry.question, answer: $answer}]' "$answers" > "$answers.tmp"
      mv "$answers.tmp" "$answers"
      remove_first
      break
      ;;
    e)
      read -r wording
      ;;
    d)
      remove_first
      break
      ;;
  esac
done
