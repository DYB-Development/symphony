#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: worktree-done.sh <worktree>

Cleans up a linked worktree once its branch is merged. The main clone is
refused.
USAGE
  exit 64
}

[ $# -eq 1 ] || usage

worktree="$(cd "$1" && pwd -P)"

[ -f "$worktree/.git" ] || {
  echo "worktree-done.sh: $worktree is not a linked worktree" >&2
  exit 65
}

[ -z "$(git -C "$worktree" status --porcelain)" ] || {
  echo "worktree-done.sh: $worktree has changes not committed" >&2
  exit 65
}

git -C "$worktree" fetch -q origin
merged_into="$(git -C "$worktree" symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/main)"

git -C "$worktree" merge-base --is-ancestor HEAD "$merged_into" || {
  echo "worktree-done.sh: $worktree has commits not merged into $merged_into" >&2
  exit 65
}

branch="$(git -C "$worktree" branch --show-current)"
main="$(git -C "$worktree" worktree list --porcelain | awk 'NR == 1 { print $2 }')"

git -C "$main" worktree remove "$worktree"
[ -z "$branch" ] || git -C "$main" branch -q -D "$branch"
