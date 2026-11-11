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
  local file
  file="$agents_dir/$(basename "$(main_clone "$1")").json"
  [ -r "$file" ] || return 0
  jq -r '.block // [] | .[]' "$file" 2>/dev/null || true
}

defined_in_repo() {
  [ -f "$1/.claude/agents/$2.md" ] || [ -f "$(main_clone "$1")/.claude/agents/$2.md" ]
}

is_blocked() {
  local name
  while IFS= read -r name; do
    [ "$name" = "$2" ] && return 0
    [ "$name" = "*" ] && defined_in_repo "$1" "$2" && return 0
  done < <(blocked_names "$1")
  return 1
}

refuse() {
  jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
    --arg text "The owner has blocked the $1 agent in this repo. Do this work in this session, or hand it to an agent that is not blocked."
}

check() {
  local payload type cwd root
  payload=$(cat)
  type=$(jq -r '.tool_input.subagent_type // empty' <<< "$payload")
  cwd=$(jq -r '.cwd // empty' <<< "$payload")
  [ -n "$type" ] && [ -d "$cwd" ] || return 0
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 0
  is_blocked "$root" "$type" || return 0
  refuse "$type"
}

case "${1:-}" in
  check) check ;;
  *) usage ;;
esac
