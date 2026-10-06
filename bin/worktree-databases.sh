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

worktree="$(cd "$2" && pwd -P)"

(cd "$worktree" && bun run worktree:db:create)
