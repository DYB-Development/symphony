#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-pr-open.sh

The pipeline's "pull request is open" check. Run by pipeline.sh inside a clone
of the work item's repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub
named, set. It passes only when the work item's branch has an open pull request.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

branch=$(git for-each-ref --format='%(refname:short)' "refs/heads/$WORK_ITEM_ID-*" | head -1)
[ -n "$branch" ] || { echo "No branch for work item $WORK_ITEM_ID"; exit 1; }

IFS=$'\t' read -r state url _ < <("$(dirname "${BASH_SOURCE[0]}")/pr-state.sh" "$branch" 2>/dev/null || true)
[ "${state:-}" = OPEN ] || { echo "No open pull request for $branch"; exit 1; }
echo "Pull request open: $url"
