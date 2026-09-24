#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: main-clone-gate.sh check  < hook.json

Keeps a repo's main clone for its owner. `check` refuses a file edit, or a git
command that changes files or the branch, aimed at a main clone, so an agent
works in a linked worktree instead. See ~/.claude/rules/agent-worktrees.md.
USAGE
  exit 64
}

nearest_dir() {
  local path="$1"
  while [ ! -d "$path" ]; do path=$(dirname "$path"); done
  printf '%s' "$path"
}

in_main_clone() {
  local dir paths
  dir=$(nearest_dir "$1")
  paths=$(git -C "$dir" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$paths" | sed -n 1p)" = "$(printf '%s\n' "$paths" | sed -n 2p)" ]
}

refuse() {
  jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
    --arg text "This is the main clone of the repo, which is kept for its owner alone."
}

payload=$(cat)

case "${1:-}" in
  check)
    path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
    [ -n "$path" ] || exit 0
    in_main_clone "$path" || exit 0
    refuse
    ;;
  *) usage ;;
esac
