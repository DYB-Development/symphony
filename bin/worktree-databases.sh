#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: worktree-databases.sh [--kind rails|package] create|drop <worktree>

Creates or drops the databases of every app found in a worktree. An app whose
root package.json has both a worktree:db:create and a worktree:db:drop script
is handled by running the matching script with Bun from the worktree's root.
On create, a Rails app whose config/database.yml carries the header
worktree-db.sh writes has its development and test databases prepared, and a
Rails app without that header is reported as not converted. Given --kind, it
acts on the apps of that kind alone.
USAGE
  exit 64
}

kind=all
if [ "${1:-}" = --kind ] && [ $# -ge 2 ]; then
  [ "$2" = rails ] || [ "$2" = package ] || usage
  kind="$2"
  shift 2
fi

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

create_rails() {
  local env
  for env in development test; do
    (cd "$worktree" && RAILS_ENV="$env" bin/rails db:prepare) || return 1
  done
}

drop_rails() {
  local named existing name
  named="$(cd "$worktree" && for env in development test; do
    RAILS_ENV="$env" bin/rails runner 'puts ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, include_hidden: true).map(&:database)' || exit 1
  done)" || return 1
  existing="$(psql -lqtA | cut -d'|' -f1)" || return 1
  for name in $named; do
    { grep -xE "$name(_[0-9]+)?" <<<"$existing" || true; } | while read -r database; do
      dropdb --if-exists "$database" || exit 1
    done || return 1
  done
}

run_package_script() {
  command -v bun >/dev/null || {
    echo "worktree-databases.sh: Bun is needed to run the package app's worktree:db:$action script, and it is not installed" >&2
    return 1
  }
  (cd "$worktree" && bun run "worktree:db:$action")
}

failed=0

attempt() {
  local app="$1"
  shift
  "$@" || {
    echo "worktree-databases.sh: could not $action the databases of the $app app in $worktree" >&2
    failed=1
  }
}

if [ "$kind" != package ] && is_converted_rails_app; then
  attempt Rails "${action}_rails"
elif [ "$kind" != package ] && [ "$action" = create ] && [ -f "$worktree/config/database.yml" ]; then
  echo "worktree-databases.sh: the Rails app in $worktree has not been converted, so its databases are shared; run worktree-db.sh on it first" >&2
fi

if [ "$kind" != rails ] && is_package_app; then
  attempt package run_package_script
fi

exit "$failed"
