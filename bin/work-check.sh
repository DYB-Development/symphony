#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-check.sh

The pipeline's check step. Run by pipeline.sh inside a clone of the work item's
repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It runs
each of the repo's test and lint entries in the work item's worktree, prints each
one's exit status, and passes only when every one exits zero. A repo with no
test entry or no lint entry fails, naming the kind it lacks.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
[ -n "$tree" ] || { echo "No worktree for work item $WORK_ITEM_ID"; exit 1; }

for kind in test lint; do
  jq -e --arg kind "$kind" 'any(.checks[]?; .kind == $kind)' <<<"$PIPELINE_STEP" >/dev/null || {
    echo "No $kind entry for $(jq -r '.work.repo' <<<"$PIPELINE_STEP")"
    exit 1
  }
done

failed=0
while IFS= read -r entry; do
  set +e
  (cd "$tree" && bash -c "$(jq -r '.check_command' <<<"$entry")")
  status=$?
  set -e
  echo "$(jq -r '.name' <<<"$entry"): exit $status"
  [ "$status" -eq 0 ] || failed=1
done < <(jq -c '.checks[]? | select(.kind == "test" or .kind == "lint")' <<<"$PIPELINE_STEP")

exit "$failed"
