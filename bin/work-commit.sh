#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-commit.sh

The pipeline's commit step. Run by pipeline.sh inside a clone of the work item's
repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It
commits every change in the work item's worktree on its branch, with the work
item's title as the subject.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
[ -n "$tree" ] || { echo "No worktree for work item $WORK_ITEM_ID"; exit 1; }

git -C "$tree" add -A
git -C "$tree" commit -q -m "$(jq -r '.work.title' <<<"$PIPELINE_STEP")"
