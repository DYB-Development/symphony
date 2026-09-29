#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: worktree-done.sh <worktree>

Cleans up a linked worktree once its branch is merged into the remote's main
branch. It drops the development and test databases the worktree's Rails app
names, including the numbered copies made for parallel tests, then removes the
worktree and deletes its local branch. It refuses the main clone, a worktree
with changes not committed, and a worktree with commits not yet merged, and
changes nothing when it refuses.
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

if grep -qF '<% worktree' "$worktree/config/database.yml" 2>/dev/null; then
  named="$(cd "$worktree" && for env in development test; do
    RAILS_ENV="$env" bin/rails runner 'puts ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, include_hidden: true).map(&:database)'
  done)"
  existing="$(psql -lqtA | cut -d'|' -f1)"
  for name in $named; do
    { grep -xE "$name(_[0-9]+)?" <<<"$existing" || true; } | while read -r database; do dropdb --if-exists "$database"; done
  done
fi

git -C "$main" worktree remove "$worktree"
[ -z "$branch" ] || git -C "$main" branch -q -D "$branch"
