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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh issue list --repo "$repo" --state all --label type:plan --limit 1000 --json number,title,body,labels,state > "$work/plans.json"
gh issue list --repo "$repo" --state all --limit 10000 --json number,title,body,labels,state |
  jq -c 'map(select(any(.labels[]; .name == "type:plan") | not)
             | {title, state, part_of: ((.body | capture("(?m)^## Part of\n(?<line>[^\n]*)").line // "") | ascii_downcase)})' \
  > "$work/tickets.json"

in_flight() {
  jq -c --slurpfile tickets "$work/tickets.json" '
    [$tickets[0][] | select(.state == "OPEN") | .part_of] as $named
    | .[] | (.title | ascii_downcase) as $group
    | select(.state == "OPEN" or any($named[]; contains($group)))' "$work/plans.json"
}

in_flight | while IFS= read -r plan; do
  printf '%s' "$plan" | jq -r '.body' > "$work/body.md"
  fields="$("$(dirname "$0")/plan-fields.sh" "$work/body.md")"
  jq -c -n --argjson plan "$plan" --argjson fields "$fields" --slurpfile tickets "$work/tickets.json" --slurpfile setting "$setting_file" '
    def completed($title): [$tickets[0][] | select(.title == $title) | .state] | length > 0 and all(. == "CLOSED");
    {title: $plan.title,
     priority: (first($plan.labels[].name | select(startswith("priority:")) | ltrimstr("priority:")) // "medium")}
    + $fields + {units: [$fields.units[] | . + {pipeline_id: $setting[0].pipeline_id}]}
    + {done_units: [$fields.units[] | select(completed(.title)) | .number]}' |
    "$hub" post move_in_plan >/dev/null
done
