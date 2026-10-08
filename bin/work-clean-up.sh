#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-clean-up.sh

The pipeline's clean-up step, run however the work ended. Run by pipeline.sh
inside a clone of the work item's repo, with WORK_ITEM_ID and PIPELINE_STEP,
the step the hub named, set. It drops the work item's worktree databases and
removes its worktree, and deletes its local branch unless the branch holds
commits that are on no remote.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

databases="${SYMPHONY_WORKTREE_DATABASES:-$(dirname "${BASH_SOURCE[0]}")/worktree-databases.sh}"

main=$(git worktree list --porcelain | awk 'NR == 1 { print $2 }')
tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
branch=$(git -C "$tree" branch --show-current)

"$databases" drop "$tree"
git -C "$main" worktree remove --force "$tree"
[ -n "$(git -C "$main" rev-list "$branch" --not --remotes)" ] || git -C "$main" branch -q -D "$branch"
echo "Removed $tree"
