#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: review-draft.sh --render <draft.json>
       review-draft.sh --link <draft.json> <comment-url>...
       review-draft.sh --post <owner/repo> <pr-number> <draft.json>

Reads the draft review written by `review-scribe`. `--render` prints it for
reading before any of it reaches the pull request. `--post` posts it, once I
have approved what `--render` showed: the inline comments go up as one review,
then the summary becomes that review's body with each `{{comment:N}}` token
pointing at the comment it names, and any replies land on the threads they
answer. `--link` does that substitution on its own.

`--post` never approves and never requests changes. Every review it posts is
event COMMENT.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

mode=${1:-}

if [ "$mode" = "--post" ]; then
  [ $# -eq 4 ] || usage
  repo=$2
  pr=$3
  draft=$4

  review=$(jq '{ event: "COMMENT", body: "Review in progress.", comments: .comments }' "$draft" \
    | gh api "repos/$repo/pulls/$pr/reviews" -X POST --input - --jq '.id')

  urls=()
  while IFS= read -r url; do
    [ -n "$url" ] && urls+=("$url")
  done < <(gh api "repos/$repo/pulls/$pr/comments" --paginate \
    --jq ".[] | select(.pull_request_review_id == $review) | .html_url")

  body=$("$0" --link "$draft" "${urls[@]+"${urls[@]}"}")

  jq -n --arg body "$body" '{ body: $body }' \
    | gh api "repos/$repo/pulls/$pr/reviews/$review" -X PUT --input - --jq '.html_url'

  replies=$(jq '.replies | length' "$draft")
  i=0
  while [ "$i" -lt "$replies" ]; do
    jq ".replies[$i] | { body }" "$draft" \
      | gh api "repos/$repo/pulls/$pr/comments/$(jq -r ".replies[$i].in_reply_to" "$draft")/replies" \
        -X POST --input - --jq '.html_url'
    i=$((i + 1))
  done

  exit 0
fi

draft=${2:-}
[ -n "$draft" ] || usage
shift 2 || usage

if [ "$mode" = "--link" ]; then
  linked=$(jq -r --args 'reduce range(0; $ARGS.positional | length) as $i (.summary;
      gsub("\\{\\{comment:" + ($i + 1 | tostring) + "\\}\\}"; $ARGS.positional[$i]))' \
    "$@" < "$draft")
  if printf '%s' "$linked" | grep -q '{{comment:'; then
    echo "review-draft.sh: the summary names a comment that was never posted" >&2
    exit 65
  fi
  printf '%s\n' "$linked"
  exit 0
fi

[ "$mode" = "--render" ] || usage
[ $# -eq 0 ] || usage

printf 'Summary comment\n\n'
jq -r '.summary' "$draft"

printf '\nInline comments (%s)\n' "$(jq -r '.comments | length' "$draft")"
jq -r '.comments | to_entries[]
  | "\n\(.key + 1). \(.value.path):\(.value.line)\n" + (.value.body | split("\n") | map(if . == "" then . else "   " + . end) | join("\n"))' "$draft"

printf '\nReplies (%s)\n' "$(jq -r '.replies | length' "$draft")"
jq -r '.replies | to_entries[]
  | "\n\(.key + 1). in reply to comment \(.value.in_reply_to)\n" + (.value.body | split("\n") | map(if . == "" then . else "   " + . end) | join("\n"))' "$draft"
