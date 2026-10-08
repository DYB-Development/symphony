#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pipeline.sh claim <work item id>
       pipeline.sh run <work item id>

Carries one work item through the steps dyb_web's Pipelines hub names.
`claim` claims the work item for this session and prints its title and first step.
`run` runs each script step the hub names, telling the hub when it starts and
reporting its exit status and output, until the work item reaches an end.
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
    esac
  done
}

case "${1:-}" in
  run) [ -n "${2:-}" ] || usage; run "$2" ;;
  claim) [ -n "${2:-}" ] || usage; claim "$2" ;;
  *) usage ;;
esac
