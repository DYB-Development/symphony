#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: dyb-hub.sh get|post <method> [<params as a JSON object>]

Calls one method of dyb_web's Pipelines hub over its JSON API and prints the
answer. Reads url= and token= from ~/.config/symphony/dyb_web.
USAGE
  exit 64
}

connection="${SYMPHONY_DYB_WEB_FILE:-$HOME/.config/symphony/dyb_web}"

value() {
  sed -n "s/^$1=//p" "$connection" | head -1
}

call() {
  local verb="$1" method="$2" reply body
  reply="$(curl -sS -w '\n%{http_code}' -X "$verb" \
    -H "Authorization: token $(value token)" \
    "$(value url)/api/v1/hubs/pipelines/$method")"
  body="${reply%$'\n'*}"
  printf '%s' "$body" | jq -c '.answer'
}

case "${1:-}" in
  get) [ $# -ge 2 ] || usage; call GET "$2" ;;
  post) [ $# -ge 2 ] || usage; call POST "$2" ;;
  *) usage ;;
esac
