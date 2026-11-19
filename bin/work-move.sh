#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-move.sh

Moves every dyb_web plan still in flight on GitHub into dyb_web production, on
the repo, pipeline and link dyb_web's work setting names.
USAGE
  exit 64
}

[ $# -eq 0 ] || usage

settings_dir="${SYMPHONY_WORK_DIR:-$HOME/.config/symphony/work}"
setting_file="$settings_dir/dyb_web.json"
hub="$(dirname "$0")/dyb-hub.sh"
repo="$(jq -r '.repo' "$setting_file")"

plans="$(gh issue list --repo "$repo" --state all --label type:plan --limit 1000 --json number,title,body,labels,state)"

printf '%s' "$plans" | jq -c '.[] | select(.state == "OPEN")' | while IFS= read -r plan; do
  body="$(mktemp)"
  printf '%s' "$plan" | jq -r '.body' > "$body"
  fields="$("$(dirname "$0")/plan-fields.sh" "$body")"
  rm -f "$body"
  jq -c -n --argjson plan "$plan" --argjson fields "$fields" '{title: $plan.title} + $fields' | "$hub" post move_in_plan >/dev/null
done
