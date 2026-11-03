#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-store.sh show|check
       work-store.sh file-plan <title> <plan-body-file>
       work-store.sh take <work-item-id>
       work-store.sh item <work-item-id>

show       Prints where the current repo keeps its plans and work: github, or
           dyb_web with the link and pipeline its setting names.
check      Asks dyb_web production for its task choices and reports whether
           it answers.
file-plan  Adds the plan to dyb_web production as a draft, linked as the
           repo's setting names, and prints its page's address.
take       Claims the work item in dyb_web production for this machine's
           session, and prints it as production reads it.
item       Prints the work item as production reads it, with the address of
           its page, without claiming it.
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
    | .repo as $repo
    | (if [$choices.pipelines[].id] | index($pipeline) then empty
       else "production holds no published pipeline with id \($pipeline)" end),
      (if $choices.repos | index($repo) then empty
       else "production holds no repo named \($repo)" end),
      ({own_project_id: "own_projects", job_id: "jobs", product_id: "products"} as $lists
       | to_entries[] | select($lists[.key]) | .key as $key | .value as $id
       | if [$choices[$lists[$key]][].id] | index($id) then empty
         else "production holds no \($key | rtrimstr("_id") | gsub("_"; " ")) with id \($id)" end)')"
  [ -z "$missing" ] || { printf '%s\n' "$missing"; return 1; }
}

file_plan() {
  local fields id
  fields="$("$(dirname "$0")/plan-fields.sh" "$2")"
  id="$(setting | jq --arg title "$1" --argjson fields "$fields" \
    '{title: $title, priority: "medium"} + (with_entries(select(.key | IN("own_project_id", "job_id", "product_id")))) + $fields' \
    | "$(dirname "$0")/dyb-hub.sh" post add_plan)"
  "$(dirname "$0")/dyb-hub.sh" page "/console/pipelines/plans/$id"
}

take() {
  jq -n --argjson id "$1" --arg session "$(whoami)@$(hostname -s)" '{work_item_id: $id, session: $session}' \
    | "$(dirname "$0")/dyb-hub.sh" post claim_work_item >/dev/null
  "$(dirname "$0")/dyb-hub.sh" get work_item "work_item_id=$1"
}

item() {
  "$(dirname "$0")/dyb-hub.sh" get work_item "work_item_id=$1" \
    | jq -c --arg address "$("$(dirname "$0")/dyb-hub.sh" page "/console/pipelines/work_items/$1")" '. + {address: $address}'
}

case "${1:-}" in
  show) show ;;
  check) check ;;
  file-plan) [ $# -eq 3 ] || usage; file_plan "$2" "$3" ;;
  take) [ $# -eq 2 ] || usage; take "$2" ;;
  item) [ $# -eq 2 ] || usage; item "$2" ;;
  *) usage ;;
esac
