#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: owner-turn.sh "<kind>" "<what is wanted>" ["<link>"]

Marks an item the owner is waited on for. The kind is one of permission,
question, pull request or plan. It prints the entry and writes nothing: the
owner's turn hook sees the call and records it against the session that made it.
USAGE
  exit 64
}

kinds="permission, question, pull request or plan"

valid_kind() {
  case "$1" in permission|question|"pull request"|plan) return 0 ;; *) return 1 ;; esac
}

record_dir="${OWNER_TURN_DIR:-$HOME/.claude/owner-turn}"
now="${OWNER_TURN_NOW:-$(date +%s)}"

repo_of() {
  git -C "$1" remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##'
}

write_entry() {
  local kind=$1 wanted=$2 link=$3 session=$4 cwd=$5
  mkdir -p "$record_dir/entries"
  jq -nc --arg kind "$kind" --arg wanted "$wanted" --arg link "$link" \
    --arg session "$session" --arg repo "$(repo_of "$cwd")" --argjson arrived "$now" \
    '{kind: $kind, wanted: $wanted, link: $link, session: $session, repo: $repo, arrived: $arrived}' \
    > "$record_dir/entries/$now-$$-$RANDOM.json"
}

record() {
  local payload session cwd command args kind wanted link
  payload=$(cat)
  session=$(printf '%s' "$payload" | jq -r '.session_id // empty')
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')
  if [ "$(printf '%s' "$payload" | jq -r '.tool_name // empty')" = AskUserQuestion ]; then
    wanted=$(printf '%s' "$payload" | jq -r '.tool_input.questions[0].question // empty')
    write_entry question "$wanted" "" "$session" "$cwd"
    return 0
  fi
  command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
  args=$(printf '%s' "$command" \
    | sed -nE 's/.*owner-turn\.sh[[:space:]]+"([^"]*)"[[:space:]]+"([^"]*)"([[:space:]]+"([^"]*)")?.*/\1\t\2\t\4/p')
  [ -n "$args" ] || return 0
  IFS=$'\t' read -r kind wanted link <<< "$args"
  valid_kind "$kind" || return 0
  write_entry "$kind" "$wanted" "$link" "$session" "$cwd"
}

if [ "${1:-}" = record ]; then
  record
  exit 0
fi

[ $# -ge 2 ] && [ $# -le 3 ] || usage

valid_kind "$1" || {
  printf 'owner-turn.sh: the kind is one of %s\n' "$kinds" >&2
  exit 64
}
