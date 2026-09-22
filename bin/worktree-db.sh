#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: worktree-db.sh [<app-dir>]

Rewrites a Rails app's config/database.yml so every git worktree of the app
gets its own development and test databases. The main clone keeps the names it
has, and a linked worktree adds its folder name to each of them. The app
directory defaults to the current one. Nothing is committed.
USAGE
  exit 64
}

[ $# -le 1 ] || usage

config="${1:-.}/config/database.yml"

[ -f "$config" ] || {
  echo "worktree-db.sh: no database config at $config" >&2
  exit 66
}

header='<% worktree = File.file?(Rails.root.join(".git")) ? "_#{Rails.root.basename.to_s.gsub(/\W/, "_")}" : "" %>'

if grep -qxF "$header" "$config"; then
  echo "$config"
  exit 0
fi

HEADER="$header" perl -pi -e '
  print "$ENV{HEADER}\n" if $. == 1;
  $section = $1 if /^(\w+):/;
  s/^(\s*database: \S+)$/$1<%= worktree %>/ if $section =~ /^(development|test)$/;
' "$config"

echo "$config"
