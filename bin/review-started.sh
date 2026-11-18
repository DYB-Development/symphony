#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: review-started.sh <owner/repo> <pr-number>

Posts one comment on the pull request saying a review has started, naming the
head commit the review reads. The review scribe runs it first on a review or a
re-review, and never on a reply.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

repo=$1 pr=$2

head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid 2>/dev/null) ||
  { echo "review-started.sh: the head commit of $repo#$pr could not be read, so nothing was posted" >&2; exit 70; }

gh pr comment "$pr" --repo "$repo" --body "Review started against ${head:0:7}."
