#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-store.sh show|check

show   Prints where the current repo keeps its plans and work: github, or
       dyb_web with the link and pipeline its setting names.
check  Asks dyb_web production for its task choices and reports whether it
       answers.
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
  local file store
  file="$settings_dir/$(repo_name).json"
  [ -r "$file" ] || { printf '{"store": "github"}'; return 0; }

  store="$(jq -r '.store' "$file")"
  case "$store" in
    github | dyb_web) cat "$file" ;;
    *) printf 'work-store.sh: %s names store "%s", which is neither github nor dyb_web\n' "$file" "$store" >&2; exit 1 ;;
  esac
}

show() {
  setting | jq -r '.store, (del(.store) | to_entries[] | "\(.key)=\(.value)")'
}

check() {
  local choices missing
  choices="$("$(dirname "$0")/dyb-hub.sh" get task_choices)"
  printf 'production answers\n'

  missing="$(setting | jq -r --argjson choices "$choices" '
    .pipeline_id as $pipeline
    | if [$choices.pipelines[].id] | index($pipeline) then empty
      else "production holds no published pipeline with id \($pipeline)" end')"
  [ -z "$missing" ] || { printf '%s\n' "$missing"; return 1; }
}

case "${1:-}" in
  show) show ;;
  check) check ;;
  *) usage ;;
esac
