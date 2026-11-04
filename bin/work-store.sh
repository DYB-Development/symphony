#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-store.sh show|check
       work-store.sh file-plan <title> <plan-body-file>
       work-store.sh file-item <title> <task-body-file> [<work-item-id> ...]
       work-store.sh take <work-item-id>
       work-store.sh take-next
       work-store.sh item <work-item-id>
       work-store.sh branch-item <branch>
       work-store.sh plan-progress <owner/repo> <task> <branch>
       work-store.sh name
       work-store.sh tick-refusal <owner/repo>
       work-store.sh ticket-criteria <owner/repo> <pr-number>

show       Prints where the current repo keeps its plans and work: github, or
           dyb_web with the link and pipeline its setting names.
check      Asks dyb_web production for its task choices and reports whether
           it answers.
file-plan  Adds the plan to dyb_web production as a draft, linked as the
           repo's setting names, and prints its page's address.
file-item  Adds the task to dyb_web production as a work item on the
           pipeline and link the setting names, waiting on the work item ids
           named after the body, and prints its page's address.
take       Takes the work item by hand in dyb_web production for this
           machine's session, starting no pipeline run, and prints it as
           production reads it.
take-next  Takes the next ready work item by hand for the repo the setting
           names, starting no pipeline run, and prints it with its id as
           production reads it.
item       Prints the work item as production reads it, with the address of
           its page, without claiming it.
branch-item
           Prints the work item a branch names, or nothing when the branch
           names none.
plan-progress
           Prints the line plan-progress.sh prints, from the plan of the work
           item the branch names in a dyb_web repo, and from GitHub otherwise.
name       Prints the store's name as a person reads it: GitHub or dyb_web.
tick-refusal
           Prints why a criterion cannot be ticked on the named repo, or nothing
           when it can.
ticket-criteria
           Prints the ticket a pull request belongs to and its acceptance
           criteria as JSON, or nothing when it names no ticket: the work item
           its branch names in a dyb_web repo, the GitHub issue it closes
           otherwise.
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

file_item() {
  local id
  id="$(setting | jq --arg title "$1" --rawfile body "$2" '
    ($body | capture("(?m)^## Acceptance criteria\n(?<text>[\\s\\S]*?)(?=\n## |\\z)").text) as $criteria
    | with_entries(select(.key | IN("repo", "pipeline_id", "own_project_id", "job_id", "product_id")))
    + {title: $title,
       request: ($body | sub("## Acceptance criteria\n[\\s\\S]*?\n(?=## )"; "")),
       acceptance_criteria: ([$criteria | scan("(?m)^- (?:\\[[ x]\\] )?(.+)$")[0]] | join("\n")),
       waits_on_ids: ($ARGS.positional | map(tonumber))}' --args "${@:3}" \
    | "$(dirname "$0")/dyb-hub.sh" post add_work_item)"
  "$(dirname "$0")/dyb-hub.sh" page "/console/pipelines/work_items/$id"
}

take() {
  jq -n --argjson id "$1" --arg session "$(whoami)@$(hostname -s)" '{work_item_id: $id, session: $session}' \
    | "$(dirname "$0")/dyb-hub.sh" post take_work_item >/dev/null
  "$(dirname "$0")/dyb-hub.sh" get work_item "work_item_id=$1"
}

take_next() {
  local id
  id="$(setting | jq --arg session "$(whoami)@$(hostname -s)" '{session: $session, repo: .repo}' \
    | "$(dirname "$0")/dyb-hub.sh" post take_next_work_item)"
  "$(dirname "$0")/dyb-hub.sh" get work_item "work_item_id=$id" | jq -c --argjson id "$id" '. + {id: $id}'
}

item() {
  "$(dirname "$0")/dyb-hub.sh" get work_item "work_item_id=$1" \
    | jq -c --arg address "$("$(dirname "$0")/dyb-hub.sh" page "/console/pipelines/work_items/$1")" '. + {address: $address}'
}

branch_item() {
  [[ "${1%%-*}" =~ ^[0-9]+$ ]] || return 0
  local found status=0
  found="$("$(dirname "$0")/dyb-hub.sh" get work_item "work_item_id=${1%%-*}" 2>&1)" || status=$?
  [ "$status" -ne 3 ] || return 0
  [ "$status" -eq 0 ] || { printf '%s\n' "$found" >&2; exit "$status"; }
  printf '%s' "$found" | jq -c --arg branch "$1" 'select(.branch == $branch)'
}

store_name() { setting | jq -r '.store'; }

name() { [ "$(store_name)" = dyb_web ] && printf 'dyb_web\n' || printf 'GitHub\n'; }

tick_refusal() {
  [ "$(setting | jq -r 'select(.store == "dyb_web") | .repo')" = "$1" ] || return 0
  printf '%s keeps its work in dyb_web, whose work items have no boxes to tick, so nothing changed.\n' "$1"
}

ticket_criteria() {
  local repo="$1" pr="$2"
  if [ "$(store_name)" = dyb_web ]; then
    local head item
    head=$(gh pr view "$pr" --repo "$repo" --json headRefName --jq '.headRefName')
    item=$(branch_item "$head") || exit 70
    [ -n "$item" ] || return 0
    printf '%s' "$item" | jq -c --argjson ticket "${head%%-*}" '{ticket: $ticket, criteria: .acceptance_criteria}'
    return 0
  fi

  local ticket
  ticket=$(gh pr view "$pr" --repo "$repo" --json closingIssuesReferences --jq '.closingIssuesReferences[0].number // empty')
  if [ -z "$ticket" ]; then
    ticket=$(gh pr view "$pr" --repo "$repo" --json body --jq '.body' |
      grep -ioE '^(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+' | head -n 1 | grep -oE '[0-9]+$' || true)
  fi
  [ -n "$ticket" ] || return 0

  gh issue view "$ticket" --repo "$repo" --json body --jq '.body' | awk '
    /^## Acceptance criteria/ { on = 1; next }
    /^## / { on = 0 }
    on && /^- \[[ xX]\] / { sub(/^- \[[ xX]\] /, ""); print }
  ' | jq -Rsc --argjson ticket "$ticket" '{ticket: $ticket, criteria: (split("\n") | map(select(length > 0)))}'
}

plan_progress() {
  [ "$(store_name)" = dyb_web ] || exec "$(dirname "$0")/plan-progress.sh" "$1" "$2"

  local item
  item=$(branch_item "$3") || exit 69
  printf '%s' "$item" | jq -e '.plan' >/dev/null || exit 1
  printf '%s' "$item" | jq -r '
    .plan | [.title,
             ([.stages[].done] | add),
             ([.stages[].total] | add),
             "stage \(.stage) of 4 — \(["End to end", "Enrich", "Simplify", "Harden"][.stage - 1])",
             ([.stages[] | "\(.stage):\(.done)/\(.total)"] | join(" ")),
             "0/0"] | @tsv'
}

case "${1:-}" in
  show) show ;;
  check) check ;;
  file-plan) [ $# -eq 3 ] || usage; file_plan "$2" "$3" ;;
  file-item) [ $# -ge 3 ] || usage; shift; file_item "$@" ;;
  take) [ $# -eq 2 ] || usage; take "$2" ;;
  take-next) [ $# -eq 1 ] || usage; take_next ;;
  item) [ $# -eq 2 ] || usage; item "$2" ;;
  branch-item) [ $# -eq 2 ] || usage; branch_item "$2" ;;
  plan-progress) [ $# -eq 4 ] || usage; plan_progress "$2" "$3" "$4" ;;
  ticket-criteria) [ $# -eq 3 ] || usage; ticket_criteria "$2" "$3" ;;
  name) name ;;
  tick-refusal) [ $# -eq 2 ] || usage; tick_refusal "$2" ;;
  *) usage ;;
esac
