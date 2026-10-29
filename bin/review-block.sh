#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: review-block.sh start  < hook.json
       review-block.sh check  < hook.json
       review-block.sh clear  < hook.json

Keeps a session that is reviewing a pull request from changing code. `start`
marks the session as reviewing when it spawns the review scribe. `check`
refuses, while the session is marked, a file edit outside its temporary
folders and the review draft, and a git command that commits, pushes,
merges, rebases or resets, and a run of the repo's tests. `clear` removes the
mark once a shell command has posted the review with review-draft.sh --post
or dropped it with review-block.sh drop.
See ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

mark_dir="${CLAUDE_REVIEW_BLOCK_DIR:-$HOME/.claude/review-block}"

mark_for() {
  printf '%s/%s' "$mark_dir" "$(printf '%s' "$1" | shasum | cut -c1-40)"
}

modified_at() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

is_reviewing() {
  local mark
  mark=$(mark_for "$session")
  [ -f "$mark" ] || return 1
  [ $(( $(date +%s) - $(modified_at "$mark") )) -le 86400 ]
}

pull_request_named() {
  local repo number
  repo=$(printf '%s' "$1" | grep -Eo '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1)
  number=$(printf '%s' "$1" | grep -Eio '(#|PR +#?|pull request +#?)[0-9]+' | head -1 | grep -Eo '[0-9]+$')
  if [ -n "$number" ]; then
    printf '%s#%s' "$repo" "$number"
  else
    printf 'a pull request'
  fi
}

in_temporary_folder() {
  local root
  for root in "${TMPDIR:-/tmp}" /tmp /private/tmp /var/folders /private/var/folders; do
    case "$1" in "${root%/}"/*) return 0 ;; esac
  done
  return 1
}

is_review_draft() {
  printf '%s' "${1##*/}" | grep -Eq '^\.review-[0-9]+(\.[a-z]+)*\.json$'
}

without_quoted_text() {
  printf '%s' "$1" | tr '\n' ';' | sed "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g"
}

changes_history() {
  without_quoted_text "$1" \
    | grep -Eq '(^|[;&|(]) *([A-Za-z_]+=[^ ]* +)*git( +-[Cc] +[^ ;&|]+)* +(commit|push|merge|rebase|reset)([^A-Za-z-]|$)'
}

runs_tests() {
  without_quoted_text "$1" \
    | grep -Eq '(^|[;&|(]) *([A-Za-z_]+=[^ ]* +)*(bin/rails +test|bundle +exec +rspec|rspec|bun +test|npm +test|yarn +test|pnpm +test|\./run_tests\.sh)([^A-Za-z-]|$)'
}

posts_review() {
  without_quoted_text "$1" | grep -Eq 'review-draft\.sh +--post( |$)'
}

drops_review() {
  without_quoted_text "$1" | grep -Eq 'review-block\.sh +drop( |;|&|$)'
}

refuse() {
  jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
    --arg text "This session is reviewing $(cat "$(mark_for "$session")"), so it only reads code and writes the review. It edits no file outside its temporary folders, commits nothing and runs no tests. If the owner asked for a fix, post the review with ~/.claude/bin/review-draft.sh --post or drop it with ~/.claude/bin/review-block.sh drop first, then do the fix as its own task."
}

payload=$(cat)
session="" agent_type="" path="" command="" prompt=""
fields=$(printf '%s' "$payload" | jq -r '
  def text: (. // "") | tostring | sub("\n+\\z"; "");
  @sh "session=\(.session_id | text) agent_type=\(.tool_input.subagent_type | text) path=\(.tool_input.file_path // .tool_input.notebook_path | text) command=\(.tool_input.command | text) prompt=\(.tool_input.prompt | text)"')
eval "$fields"
[ -n "$session" ] || exit 0

case "${1:-}" in
  start)
    [ "$agent_type" = "review-scribe" ] || exit 0
    mkdir -p "$mark_dir"
    pull_request_named "$prompt" > "$(mark_for "$session")"
    ;;
  check)
    is_reviewing || exit 0
    if [ -n "$command" ]; then
      changes_history "$command" || runs_tests "$command" || exit 0
      refuse
      exit 0
    fi
    in_temporary_folder "$path" && exit 0
    is_review_draft "$path" && exit 0
    refuse
    ;;
  clear)
    posts_review "$command" || drops_review "$command" || exit 0
    rm -f "$(mark_for "$session")"
    ;;
  *) usage ;;
esac
