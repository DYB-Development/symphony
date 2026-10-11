#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-new-test-fails.sh

The pipeline's "new test fails" check. Run by pipeline.sh inside a clone of the
work item's repo, with WORK_ITEM_ID and PIPELINE_STEP, the step the hub named,
set. It runs the repo's test entry with the new test's file added to the end, in
the work item's worktree, and passes only when that test fails.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

tree=$(git worktree list --porcelain | awk -v prefix="branch refs/heads/$WORK_ITEM_ID-" '/^worktree / { tree = substr($0, 10) } index($0, prefix) == 1 { print tree; exit }')
[ -n "$tree" ] || { echo "No worktree for work item $WORK_ITEM_ID"; exit 1; }

files=$(git -C "$tree" ls-files --others --modified --exclude-standard | grep -E '(^|/)(test|tests|spec|__tests__)/' | tr '\n' ' ' || true)
[ -n "$files" ] || { echo "No new test was written"; exit 1; }
command=$(jq -r 'first(.checks[]? | select(.kind == "test")) | .check_command' <<<"$PIPELINE_STEP")

set +e
output=$(cd "$tree" && bash -c "$command $files" 2>&1)
status=$?
set -e

[ "$status" -ne 0 ] || { echo "The new test passed before any code was written"; exit 1; }
echo "The new test fails"
printf '%s\n' "$output"
