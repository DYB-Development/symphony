#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-push.sh

The pipeline's push step. Run by pipeline.sh inside a clone of the work item's
repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It runs
the check step again and pushes the work item's branch only when the check
passes and nothing in its worktree is uncommitted.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

"$(dirname "${BASH_SOURCE[0]}")/work-check.sh"

tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
[ -z "$(git -C "$tree" status --porcelain)" ] || { echo "Something is uncommitted in $tree"; exit 1; }

git -C "$tree" push -q -u origin "$(git -C "$tree" branch --show-current)"
echo "Pushed $(git -C "$tree" branch --show-current)"
