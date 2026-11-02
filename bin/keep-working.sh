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

commits_ahead() {
  local worktree=$1 base
  shift
  for base in "$@"; do
    git -C "$worktree" rev-parse -q --verify "$base" >/dev/null 2>&1 || continue
    git -C "$worktree" rev-list --count "$base..HEAD"
    return 0
  done
  printf '0\n'
}

hook=$(cat)
transcript=$(jq -r '.transcript_path // empty' <<< "$hook")
worktree=$(session_worktree "$transcript")
[ -n "$worktree" ] || exit 0

unfinished=()
[ -z "$(git -C "$worktree" status --porcelain)" ] || unfinished+=("uncommitted changes")
[ "$(commits_ahead "$worktree" '@{upstream}' origin/HEAD origin/main)" -eq 0 ] || unfinished+=("unpushed commits")

[ ${#unfinished[@]} -gt 0 ] || exit 0
jq -nc --arg reason "This branch has $(IFS=,; printf '%s' "${unfinished[*]}"). Keep working." '{decision: "block", reason: $reason}'
