#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: decision-gate.sh arm    < hook.json
       decision-gate.sh check  < hook.json

Holds a session to its own decision log. `arm` records a choice the moment one is
settled through a question; `check` refuses a commit while that choice is still
unrecorded in the .decisions.md of the repo being committed to.
See ~/.claude/rules/decision-log.md.
USAGE
  exit 64
}

marker_dir="${CLAUDE_DECISION_GATE_DIR:-$HOME/.claude/decision-gate}"

marker_for() {
  printf '%s/%s' "$marker_dir" "$(printf '%s' "$*" | shasum | cut -c1-40)"
}

modified_at() {
  [ -e "$1" ] || { printf '0'; return; }
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

first_dir() {
  printf '%s' "$2" \
    | grep -Eo "$1" \
    | head -1 \
    | sed -E "s/^.*(-C|cd) +//; s/^['\"]//; s/['\"]$//"
}

commit_root() {
  local dir
  dir=$(first_dir "git +-C +('[^']*'|\"[^\"]*\"|[^ ;&|]+)" "$1")
  [ -n "$dir" ] || dir=$(first_dir "(^|[;&|] *)cd +('[^']*'|\"[^\"]*\"|[^ ;&|]+)" "$1")
  dir=${dir/#\~/$HOME}
  git -C "${dir:-.}" rev-parse --show-toplevel 2>/dev/null
}

payload=$(cat)
session=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -n "$session" ] || exit 0

case "${1:-}" in
  arm)
    mkdir -p "$marker_dir"
    : > "$(marker_for "$session")"
    jq -nc '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $text}}' \
      --arg text "A question was just answered, which settles a choice between real options. Record it now, before the next line of code: ~/.claude/bin/decide.sh \"<the question>\" \"<the decision>\". A commit is refused until the log carries it. If this answer settled nothing worth a reviewer's attention, prefix the commit with NO_DECISION=1."
    ;;
  check)
    marker=$(marker_for "$session")
    [ -f "$marker" ] || exit 0
    command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    printf '%s' "$command" | grep -Eq "(^|[^A-Za-z])git([^A-Za-z]|$)" || exit 0
    printf '%s' "$command" | grep -Eq "(^|[^A-Za-z])commit([^A-Za-z]|$)" || exit 0
    root=$(commit_root "$command") || exit 0
    [ -n "$root" ] || exit 0
    armed=$(modified_at "$marker")
    [ "$(modified_at "$root/.decisions.md")" -lt "$armed" ] || exit 0
    cleared=$(marker_for "$session" "$root")
    [ "$(modified_at "$cleared")" -lt "$armed" ] || exit 0
    # Quoted spans are stripped first, so the override counts only as an
    # environment assignment on the command and never as prose in the message.
    unquoted=$(printf '%s' "$command" | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")
    case "$unquoted" in *NO_DECISION=1*) mkdir -p "$marker_dir"; : > "$cleared"; exit 0;; esac
    jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
      --arg text "A question answered earlier in this session settled a choice between real options, and .decisions.md does not carry it yet. Record it before committing: ~/.claude/bin/decide.sh \"<the question>\" \"<the decision>\". If that answer settled nothing a reviewer needs, prefix this command with NO_DECISION=1."
    ;;
  *) usage ;;
esac
