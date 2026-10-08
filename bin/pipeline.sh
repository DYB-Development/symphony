#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pipeline.sh claim <work item id>
       pipeline.sh run <work item id>
       pipeline.sh report <work item id> <agent report file>

Carries one work item through the steps dyb_web's Pipelines hub names.
`claim` claims the work item for this session and prints its title and first step.
`run` runs each script step the hub names, telling the hub when it starts and
reporting its exit status and output, until the work item reaches an end.
It stops with status 10 at an agent step, printing the agent, its model and the work.
At the owner's step it reports the pull request of the work item's branch as merged
or closed, or stops with status 11 while the pull request is still open. The
work item's branch is the local branch whose name starts with its id.
`report` posts an agent's report for the agent step the work item is on, with
the result its last line names, written as Result: passed or Result: failed.
The dyb_web address and token are read from the dyb_web file in
$SYMPHONY_CONFIG_DIR, or ~/.config/symphony, one name=value per line.
USAGE
  exit 64
}

settings="${SYMPHONY_CONFIG_DIR:-$HOME/.config/symphony}/dyb_web"
session="${SYMPHONY_SESSION:-$(hostname -s)}"
steps="${SYMPHONY_STEP_DIR:-$(cd "$(dirname "$0")" && pwd)}"

setting() { sed -n "s/^$1=//p" "$settings" 2>/dev/null | tail -1; }

hub() {
  local method="$1" name="$2" body="${3:-}" reply status
  local address
  address="$(setting url)/api/v1/hubs/pipelines/$name"
  if [ "$method" = GET ]; then
    reply=$(curl -sS -w '\n%{http_code}' -H "Authorization: token $(setting token)" "$address?$body" 2>/dev/null) || refuse 69 "dyb_web cannot be reached at $(setting url)"
  else
    reply=$(curl -sS -w '\n%{http_code}' -H "Authorization: token $(setting token)" -H "Content-Type: application/json" -d "$body" "$address" 2>/dev/null) || refuse 69 "dyb_web cannot be reached at $(setting url)"
  fi
  status=$(printf '%s' "$reply" | tail -1)
  case "$status" in
    401 | 403 | 404) refuse 77 "dyb_web refused the token" ;;
    2??) printf '%s' "$reply" | sed '$d' | jq -c '.answer' ;;
    *) refuse 65 "$(printf '%s' "$reply" | sed '$d' | jq -r '.error // empty' 2>/dev/null | grep . || echo "dyb_web answered $status")" ;;
  esac
}

refuse() {
  echo "$2" >&2
  exit "$1"
}

claim() {
  local id="$1" step
  hub POST claim_work_item "$(jq -nc --argjson id "$id" --arg session "$session" '{work_item_id: $id, session: $session}')" >/dev/null
  step=$(hub GET current_step "work_item_id=$id")
  printf 'Claimed %s\nFirst step: %s\n' "$(jq -r '.work.title' <<<"$step")" "$(jq -r '.name' <<<"$step")"
}

run_script() {
  local id="$1" step="$2" name script output status result
  name=$(jq -r '.id' <<<"$step")
  script="$steps/$(jq -r '.script' <<<"$step").sh"
  [ -x "$script" ] || refuse 66 "symphony has no script named $(jq -r '.script' <<<"$step")"
  hub POST start_step "$(jq -nc --argjson id "$id" --arg step "$name" '{work_item_id: $id, step: $step}')" >/dev/null
  set +e
  output=$(PIPELINE_STEP="$step" WORK_ITEM_ID="$id" "$script" 2>&1)
  status=$?
  set -e
  result=passed
  [ "$status" -eq 0 ] || result=failed
  hub POST report_step "$(jq -nc --argjson id "$id" --arg step "$name" --arg result "$result" --argjson status "$status" --arg output "$output" \
    '{work_item_id: $id, step: $step, result: $result, exit_status: $status, output: $output}')" >/dev/null
}

hand_to_agent() {
  jq -r '"Agent step: \(.name)\nAgent: \(.agent)\nModel: \(.model)\nTitle: \(.work.title)\nRequest: \(.work.request)\nAcceptance criteria: \(.work.acceptance_criteria)"' <<<"$1"
  exit 10
}

work_branch() {
  git for-each-ref --format='%(refname:short)' "refs/heads/$1-*" | head -1 | grep . || refuse 66 "no branch for work item $1 in this repo"
}

owner_step() {
  local id="$1" step="$2" pull state result
  pull=$(gh pr view "$(work_branch "$id")" --json state,url)
  state=$(jq -r '.state' <<<"$pull")
  case "$state" in
    MERGED) result=passed ;;
    CLOSED) result=failed ;;
    *)
      printf '%s waits on the owner: %s\n' "$(jq -r '.work.title' <<<"$step")" "$(jq -r '.url' <<<"$pull")"
      exit 11
      ;;
  esac
  hub POST report_step "$(jq -nc --argjson id "$id" --arg step "$(jq -r '.id' <<<"$step")" --arg result "$result" --arg output "$(tr '[:upper:]' '[:lower:]' <<<"$state")" \
    '{work_item_id: $id, step: $step, result: $result, output: $output}')" >/dev/null
}

run() {
  local id="$1" step
  while :; do
    step=$(hub GET current_step "work_item_id=$id")
    if [ "$(jq -r '.done // false' <<<"$step")" = true ]; then
      printf 'Done: %s\n' "$(jq -r '.output // "no output"' <<<"$step")"
      return 0
    fi
    case "$(jq -r '.kind' <<<"$step")" in
      script) run_script "$id" "$step" ;;
      agent) hand_to_agent "$step" ;;
      owner) owner_step "$id" "$step" ;;
      *) refuse 65 "symphony cannot run a $(jq -r '.kind' <<<"$step") step" ;;
    esac
  done
}

report_agent() {
  local id="$1" file="$2" step result
  step=$(hub GET current_step "work_item_id=$id")
  result=$(grep -v '^[[:space:]]*$' "$file" | tail -1 | sed -nE 's/^Result: (passed|failed)[[:space:]]*$/\1/p')
  hub POST report_step "$(jq -nc --argjson id "$id" --arg step "$(jq -r '.id' <<<"$step")" --arg result "$result" --rawfile output "$file" \
    '{work_item_id: $id, step: $step, result: $result, output: ($output | rtrimstr("\n"))}')" >/dev/null
}

case "${1:-}" in
  report) [ -n "${3:-}" ] || usage; report_agent "$2" "$3" ;;
  run) [ -n "${2:-}" ] || usage; run "$2" ;;
  claim) [ -n "${2:-}" ] || usage; claim "$2" ;;
  *) usage ;;
esac
