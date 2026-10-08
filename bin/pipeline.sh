#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: pipeline.sh claim <work item id>

Carries one work item through the steps dyb_web's Pipelines hub names.
`claim` claims the work item for this session and prints its title and first step.
The dyb_web address and token are read from the dyb_web file in
$SYMPHONY_CONFIG_DIR, or ~/.config/symphony, one name=value per line.
USAGE
  exit 64
}

settings="${SYMPHONY_CONFIG_DIR:-$HOME/.config/symphony}/dyb_web"
session="${SYMPHONY_SESSION:-$(hostname -s)}"

setting() { sed -n "s/^$1=//p" "$settings" 2>/dev/null | tail -1; }

hub() {
  local method="$1" name="$2" body="${3:-}" reply
  local address
  address="$(setting url)/api/v1/hubs/pipelines/$name"
  if [ "$method" = GET ]; then
    reply=$(curl -sS -w '\n%{http_code}' -H "Authorization: token $(setting token)" "$address?$body")
  else
    reply=$(curl -sS -w '\n%{http_code}' -H "Authorization: token $(setting token)" -H "Content-Type: application/json" -d "$body" "$address")
  fi
  printf '%s' "$reply" | sed '$d' | jq -c '.answer'
}

claim() {
  local id="$1" step
  hub POST claim_work_item "$(jq -nc --argjson id "$id" --arg session "$session" '{work_item_id: $id, session: $session}')" >/dev/null
  step=$(hub GET current_step "work_item_id=$id")
  printf 'Claimed %s\nFirst step: %s\n' "$(jq -r '.work.title' <<<"$step")" "$(jq -r '.name' <<<"$step")"
}

case "${1:-}" in
  claim) [ -n "${2:-}" ] || usage; claim "$2" ;;
  *) usage ;;
esac
