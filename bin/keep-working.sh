#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: keep-working.sh check < hook.json

Refuses a stop while the branch the session is working on has unfinished work.
See ~/.claude/rules/develop_process_rules.md.
USAGE
  exit 64
}

[ "${1:-}" = check ] || usage

index="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/session-worktrees.tsv"

is_linked_worktree() {
  [ "$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" != "$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]
}

session_worktree() {
  local root
  [ -f "$index" ] || return 0
  while IFS= read -r root; do
    is_linked_worktree "$root" && { printf '%s\n' "$root"; return 0; }
  done < <(awk -F '\t' -v t="$1" '$2 == t { print $1 }' "$index" | tail -r)
}

hook=$(cat)
transcript=$(jq -r '.transcript_path // empty' <<< "$hook")
worktree=$(session_worktree "$transcript")
[ -n "$worktree" ] || exit 0
[ -n "$(git -C "$worktree" status --porcelain)" ] || exit 0
jq -nc --arg reason "This branch has uncommitted changes. Keep working." '{decision: "block", reason: $reason}'
