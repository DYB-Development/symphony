#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: worktree-databases.sh create|drop <worktree>

Creates or drops the databases of every app found in a worktree. An app whose
root package.json has both a worktree:db:create and a worktree:db:drop script
is handled by running the matching script with Bun from the worktree's root.
On create, a Rails app whose config/database.yml carries the header
worktree-db.sh writes has its development and test databases prepared, and a
Rails app without that header is reported as not converted.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage
[ "$1" = create ] || [ "$1" = drop ] || usage
[ -e "$2/.git" ] || usage

action="$1"
worktree="$(cd "$2" && pwd -P)"

is_package_app() {
  jq -e '.scripts["worktree:db:create"] and .scripts["worktree:db:drop"]' "$worktree/package.json" >/dev/null 2>&1
}

is_converted_rails_app() {
  head -1 "$worktree/config/database.yml" 2>/dev/null | grep -qF 'worktree = '
}

if [ "$action" = create ] && is_converted_rails_app; then
  for env in development test; do
    (cd "$worktree" && RAILS_ENV="$env" bin/rails db:prepare)
  done
elif [ "$action" = create ] && [ -f "$worktree/config/database.yml" ]; then
  echo "worktree-databases.sh: the Rails app in $worktree has not been converted, so its databases are shared; run worktree-db.sh on it first" >&2
fi

if is_package_app; then
  (cd "$worktree" && bun run "worktree:db:$action")
fi
