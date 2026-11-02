#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-store.sh show

show  Prints where the current repo keeps its plans and work: github, or
      dyb_web with the link and pipeline its setting names.
USAGE
  exit 64
}

settings_dir="${SYMPHONY_WORK_DIR:-$HOME/.config/symphony/work}"

repo_name() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  basename "$(dirname "$common")"
}

setting() {
  local file
  file="$settings_dir/$(repo_name).json"
  [ -r "$file" ] && cat "$file" || printf '{"store": "github"}'
}

show() {
  setting | jq -r '.store, (del(.store) | to_entries[] | "\(.key)=\(.value)")'
}

case "${1:-}" in
  show) show ;;
  *) usage ;;
esac
