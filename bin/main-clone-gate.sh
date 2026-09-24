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

changes_files_or_branch() {
  printf '%s' "$1" | grep -Eq '(^|[;&|(]) *([A-Za-z_]+=[^ ]* +)*git( +-[Cc] +[^ ;&|]+)* +(commit|checkout|switch|merge|rebase|reset|stash|pull)([^A-Za-z-]|$)'
}

first_dir() {
  printf '%s' "$2" \
    | grep -Eo "$1" \
    | head -1 \
    | sed -E "s/^.*(-C|cd) +//; s/^['\"]//; s/['\"]$//"
}

target_dir() {
  local command="$1" cwd="$2" dir
  dir=$(first_dir "git +-C +('[^']*'|\"[^\"]*\"|[^ ;&|]+)" "$command")
  [ -n "$dir" ] || dir=$(first_dir "(^|[;&|] *)cd +('[^']*'|\"[^\"]*\"|[^ ;&|]+)" "$command")
  dir=${dir/#\~/$HOME}
  case "$dir" in
    "") printf '%s' "$cwd" ;;
    /*) printf '%s' "$dir" ;;
    *)  printf '%s/%s' "$cwd" "$dir" ;;
  esac
}

payload=$(cat)

case "${1:-}" in
  check)
    command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    if [ -n "$command" ]; then
      changes_files_or_branch "$command" || exit 0
      cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')
      in_main_clone "$(target_dir "$command" "$cwd")" || exit 0
      refuse
      exit 0
    fi
    path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
    [ -n "$path" ] || exit 0
    in_main_clone "$path" || exit 0
    refuse
    ;;
  *) usage ;;
esac
