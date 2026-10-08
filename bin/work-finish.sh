#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-finish.sh

The pipeline's finish step. Run by pipeline.sh inside a clone of the work item's
repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It fails,
changing nothing, while the pull request of the work item's branch is not merged.
Once it is merged, it removes the worktree's decision log, ticket and resume
bookmark, then removes the worktree, its databases and its branch through
worktree-done.sh.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
[ -n "$tree" ] || { echo "No worktree for work item $WORK_ITEM_ID"; exit 1; }
branch=$(git -C "$tree" branch --show-current)

[ "$("$(dirname "${BASH_SOURCE[0]}")/pr-state.sh" "$branch" | cut -f1)" = MERGED ] || {
  echo "The pull request for $branch is not merged"
  exit 1
}

rm -f "$tree/.decisions.md" "$tree/.ticket" "$tree/start_here.md"
"$(dirname "${BASH_SOURCE[0]}")/worktree-done.sh" "$tree"
echo "Removed $tree"
