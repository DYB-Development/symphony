#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: review-block.sh start  < hook.json

Keeps a session that is reviewing a pull request from changing code. `start`
marks the session as reviewing when it spawns the review scribe.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

mark_dir="${CLAUDE_REVIEW_BLOCK_DIR:-$HOME/.claude/review-block}"

mark_for() {
  printf '%s/%s' "$mark_dir" "$(printf '%s' "$1" | shasum | cut -c1-40)"
}

payload=$(cat)
session="" agent_type=""
fields=$(printf '%s' "$payload" | jq -r '
  def text: (. // "") | tostring | sub("\n+\\z"; "");
  @sh "session=\(.session_id | text) agent_type=\(.tool_input.subagent_type | text)"')
eval "$fields"
[ -n "$session" ] || exit 0

case "${1:-}" in
  start)
    [ "$agent_type" = "review-scribe" ] || exit 0
    mkdir -p "$mark_dir"
    : > "$(mark_for "$session")"
    ;;
  *) usage ;;
esac
