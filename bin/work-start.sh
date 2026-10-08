#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-start.sh

The pipeline's start step. Run by pipeline.sh inside a clone of the work item's
repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It makes
the work item's worktree beside the main clone, on a branch named after the work
item's id and title, and creates the worktree's databases. A work item whose
worktree already exists keeps that worktree and gets no second one. It then runs each of
the repo's setup entries in the worktree, runs an entry's fix command when its
check fails, and fails showing the entry's instruction when the check still fails.
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

existing=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')

if [ -n "$existing" ]; then
  tree="$existing"
  echo "Worktree already at $tree"
else
  git -C "$main" fetch -q origin
  git -C "$main" worktree add -q -b "$branch" "$tree" origin/main
  "$databases" create "$tree"
  echo "Worktree: $tree"
fi

set_up() {
  local entry="$1" name check fix
  name=$(jq -r '.name' <<<"$entry")
  check=$(jq -r '.check_command' <<<"$entry")
  fix=$(jq -r '.fix_command // ""' <<<"$entry")
  (cd "$tree" && bash -c "$check") && return 0
  [ -z "$fix" ] || (cd "$tree" && bash -c "$fix") || true
  (cd "$tree" && bash -c "$check") && return 0
  echo "$name is not set up."
  jq -r '.instruction // ""' <<<"$entry"
  return 1
}

while IFS= read -r entry; do
  set_up "$entry" || exit 1
done < <(jq -c '.checks[]? | select(.kind == "setup")' <<<"$PIPELINE_STEP")
