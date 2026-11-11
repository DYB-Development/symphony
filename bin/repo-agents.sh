#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: repo-agents.sh check < hook.json

Refuses an agent the owner has blocked in a repo. Each repo's block list is read
from ~/.config/symphony/agents/<repo>.json, where <repo> is the folder name of
the repo's main clone.
USAGE
  exit 64
}

agents_dir="${SYMPHONY_AGENTS_DIR:-$HOME/.config/symphony/agents}"

main_clone() {
  dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
}

blocked_names() {
  local file="$agents_dir/$(basename "$(main_clone "$1")").json"
  [ -r "$file" ] || return 0
  jq -r '.block // [] | .[]' "$file" 2>/dev/null || true
}

refuse() {
  jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
    --arg text "The owner has blocked the $1 agent in this repo. Do this work in this session, or hand it to an agent that is not blocked."
}

check() {
  local payload type cwd name
  payload=$(cat)
  type=$(jq -r '.tool_input.subagent_type // empty' <<< "$payload")
  cwd=$(jq -r '.cwd // empty' <<< "$payload")
  [ -n "$type" ] && [ -d "$cwd" ] || return 0
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return 0
  while IFS= read -r name; do
    [ "$name" = "$type" ] || continue
    refuse "$type"
    return 0
  done < <(blocked_names "$cwd")
}

case "${1:-}" in
  check) check ;;
  *) usage ;;
esac
