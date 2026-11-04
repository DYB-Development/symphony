#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: dyb-hub.sh get <method> [<name>=<value>...]
       dyb-hub.sh post <method> < params.json
       dyb-hub.sh page <path>

Calls one method of dyb_web's Pipelines hub over its JSON API and prints the
answer. A get sends each name=value as a query value, and a post sends the
JSON object it reads as the method's params. page
prints the production address of a path. Reads url= and token= from
~/.config/symphony/dyb_web.
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
    404) printf '%s' "$body" | jq -r '.error' >&2; exit 3 ;;
    *) printf '%s' "$body" | jq -r '.error' >&2; exit 1 ;;
  esac
}

case "${1:-}" in
  get)
    [ $# -ge 2 ] || usage
    method="$2"
    shift 2
    values=()
    for value in "$@"; do values+=(--data-urlencode "$value"); done
    call GET "$method" -G "${values[@]+"${values[@]}"}"
    ;;
  post) [ $# -eq 2 ] || usage; call POST "$2" -H "Content-Type: application/json" --data-binary @- ;;
  page) [ $# -eq 2 ] || usage; printf '%s%s\n' "$(value url)" "$2" ;;
  *) usage ;;
esac
