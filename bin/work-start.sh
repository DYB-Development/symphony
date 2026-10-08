#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-start.sh

The pipeline's start step. Run by pipeline.sh inside a clone of the work item's
repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It makes
the work item's worktree beside the main clone, on a branch named after the work
item's id and title, and creates the worktree's databases.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

databases="${SYMPHONY_WORKTREE_DATABASES:-$(dirname "${BASH_SOURCE[0]}")/worktree-databases.sh}"

main=$(git worktree list --porcelain | awk 'NR == 1 { print $2 }')
title=$(jq -r '.work.title' <<<"$PIPELINE_STEP")
slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
branch="$WORK_ITEM_ID-$slug"
tree="$main-$branch"

git -C "$main" fetch -q origin
git -C "$main" worktree add -q -b "$branch" "$tree" origin/main
"$databases" create "$tree"
echo "Worktree: $tree"
