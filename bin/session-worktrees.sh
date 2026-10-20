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

worked_in() {
  jq -r '
    .cwd // empty,
    (.tool_input | objects | (.file_path, .notebook_path, .path) | strings),
    ((.tool_input.command // "") | tostring
      | scan("(?:^|[;&|(\\s])(?:cd|-C)\\s+([^\\s;&|)\u0027\"]+)") | .[0])
  ' 2>/dev/null
}

record_pair() {
  local root line
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  line="$root"$'\t'"$2"
  grep -qxF -- "$line" "$index" 2>/dev/null && return 0
  mkdir -p "$(dirname "$index")"
  printf '%s\n' "$line" >> "$index"
}

record() {
  local payload transcript path
  payload=$(cat)
  transcript=$(printf '%s' "$payload" | jq -r '
    (.transcript_path // "") as $session
    | if $session == "" then empty
      elif (.agent_id // "") == "" then $session
      else "\($session | sub("\\.jsonl$"; ""))/subagents/agent-\(.agent_id).jsonl"
      end' 2>/dev/null)
  [ -n "$transcript" ] || return 0
  printf '%s' "$payload" | worked_in | sort -u | while IFS= read -r path; do
    [ -d "$path" ] || path=$(dirname "$path")
    [ -d "$path" ] && record_pair "$path" "$transcript"
  done
}

case "${1:-}" in
  record) [ $# -eq 1 ] || usage; record 2>/dev/null; exit 0 ;;
  *) usage ;;
esac
