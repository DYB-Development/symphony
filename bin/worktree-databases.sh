#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: worktree-databases.sh create <worktree>

Creates the databases of every app found in a worktree. An app whose root
package.json has both a worktree:db:create and a worktree:db:drop script is
created by running worktree:db:create with Bun from the worktree's root.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage
[ "$1" = create ] || usage
[ -e "$2/.git" ] || usage

worktree="$(cd "$2" && pwd -P)"

is_package_app() {
  jq -e '.scripts["worktree:db:create"] and .scripts["worktree:db:drop"]' "$worktree/package.json" >/dev/null 2>&1
}

if is_package_app; then
  (cd "$worktree" && bun run worktree:db:create)
fi
