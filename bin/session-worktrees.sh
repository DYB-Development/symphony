#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: session-worktrees.sh record < hook.json

Keeps an index of which session transcripts worked in which git worktree, so
usage.sh can find work done on a branch from a session started in another repo.
`record` is the hook.
USAGE
  exit 64
}

index="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/session-worktrees.tsv"

record() {
  local payload fields cwd="" transcript="" root line
  payload=$(cat)
  fields=$(printf '%s' "$payload" | jq -r '
    def text: (. // "") | tostring;
    @sh "cwd=\(.cwd | text) transcript=\(.transcript_path | text)"')
  eval "$fields"
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 0
  line="$root"$'\t'"$transcript"
  grep -qxF -- "$line" "$index" 2>/dev/null && return 0
  mkdir -p "$(dirname "$index")"
  printf '%s\n' "$line" >> "$index"
}

case "${1:-}" in
  record) [ $# -eq 1 ] || usage; record ;;
  *) usage ;;
esac
