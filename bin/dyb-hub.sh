#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: dyb-hub.sh get <method>
       dyb-hub.sh post <method> < params.json

Calls one method of dyb_web's Pipelines hub over its JSON API and prints the
answer. A post sends the JSON object it reads as the method's params. Reads
url= and token= from ~/.config/symphony/dyb_web.
USAGE
  exit 64
}

connection="${SYMPHONY_DYB_WEB_FILE:-$HOME/.config/symphony/dyb_web}"

value() {
  sed -n "s/^$1=//p" "$connection" | head -1
}

call() {
  local verb="$1" method="$2" reply body
  shift 2
  reply="$(curl -sS -w '\n%{http_code}' -X "$verb" "$@" \
    -H "Authorization: token $(value token)" \
    "$(value url)/api/v1/hubs/pipelines/$method")"
  body="${reply%$'\n'*}"
  case "${reply##*$'\n'}" in
    2??) printf '%s' "$body" | jq -c '.answer' ;;
    *) printf '%s' "$body" | jq -r '.error' >&2; exit 1 ;;
  esac
}

case "${1:-}" in
  get) [ $# -eq 2 ] || usage; call GET "$2" ;;
  post) [ $# -eq 2 ] || usage; call POST "$2" -H "Content-Type: application/json" --data-binary @- ;;
  *) usage ;;
esac
