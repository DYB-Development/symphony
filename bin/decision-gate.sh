#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: decision-gate.sh arm    < hook.json
       decision-gate.sh check  < hook.json

Holds a session to its own decision log. `arm` records a choice the moment one is
settled through a question; `check` refuses a commit while that choice is still
unrecorded in .decisions.md.
See ~/.claude/rules/decision-log.md.
USAGE
  exit 64
}

marker_dir="${CLAUDE_DECISION_GATE_DIR:-$HOME/.claude/decision-gate}"

marker_for() {
  local session=$1 root=$2
  printf '%s/%s' "$marker_dir" "$(printf '%s\n%s' "$session" "$root" | shasum | cut -c1-40)"
}

log_size() {
  [ -f "$1/.decisions.md" ] || { printf '0'; return; }
  wc -l < "$1/.decisions.md" | tr -d ' '
}

payload=$(cat)
session=$(printf '%s' "$payload" | jq -r '.session_id // empty')
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$session" ] || exit 0

case "${1:-}" in
  arm)
    mkdir -p "$marker_dir"
    log_size "$root" > "$(marker_for "$session" "$root")"
    jq -nc '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $text}}' \
      --arg text "A question was just answered, which settles a choice between real options. Record it now, before the next line of code: ~/.claude/bin/decide.sh \"<the question>\" \"<the decision>\". A commit is refused until the log carries it. If this answer settled nothing worth a reviewer's attention, prefix the commit with NO_DECISION=1."
    ;;
  check)
    marker=$(marker_for "$session" "$root")
    [ -f "$marker" ] || exit 0
    [ "$(log_size "$root")" = "$(cat "$marker")" ] || { rm -f "$marker"; exit 0; }
    command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    printf '%s' "$command" | grep -Eq "(^|[^A-Za-z])git([^A-Za-z]|$)" || exit 0
    printf '%s' "$command" | grep -Eq "(^|[^A-Za-z])commit([^A-Za-z]|$)" || exit 0
    # Quoted spans are stripped first, so the override counts only as an
    # environment assignment on the command and never as prose in the message.
    unquoted=$(printf '%s' "$command" | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")
    case "$unquoted" in *NO_DECISION=1*) rm -f "$marker"; exit 0;; esac
    jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
      --arg text "A question answered earlier in this session settled a choice between real options, and .decisions.md does not carry it yet. Record it before committing: ~/.claude/bin/decide.sh \"<the question>\" \"<the decision>\". If that answer settled nothing a reviewer needs, prefix this command with NO_DECISION=1."
    ;;
  *) usage ;;
esac
