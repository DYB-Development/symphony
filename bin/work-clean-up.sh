#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-clean-up.sh

The pipeline's clean-up step, run however the work ended. Run by pipeline.sh
inside a clone of the work item's repo, with WORK_ITEM_ID and PIPELINE_STEP,
the step the hub named, set. It drops the work item's worktree databases and
removes its worktree. It deletes the local branch when its pull request merged,
and otherwise keeps a branch holding commits that are on no remote.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

databases="${SYMPHONY_WORKTREE_DATABASES:-$(dirname "${BASH_SOURCE[0]}")/worktree-databases.sh}"

main=$(git worktree list --porcelain | awk 'NR == 1 { print $2 }')
tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
branch=$(git -C "$main" for-each-ref --format='%(refname:short)' "refs/heads/$WORK_ITEM_ID-*" | head -1)
[ -n "$tree" ] || [ -n "$branch" ] || { echo "Nothing to remove for work item $WORK_ITEM_ID"; exit 0; }

if [ -n "$tree" ]; then
  [ "$tree" != "$main" ] || { echo "The clean-up step refuses to remove the main clone at $main"; exit 1; }
  branch=$(git -C "$tree" branch --show-current)
  rm -f "$tree/.decisions.md" "$tree/.ticket" "$tree/start_here.md"
  dropped=$("$databases" drop "$tree" 2>&1) || { echo "Dropping the databases failed: $dropped"; exit 1; }
  git -C "$main" worktree remove --force "$tree"
  echo "Removed $tree"
fi

merged=$("$(dirname "${BASH_SOURCE[0]}")/pr-state.sh" "$branch" 2>/dev/null | cut -f1 || true)
if [ "$merged" = MERGED ] || [ -z "$(git -C "$main" rev-list "$branch" --not --remotes)" ]; then
  git -C "$main" branch -q -D "$branch"
fi
