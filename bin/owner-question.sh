#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: owner-question.sh record < hook.json
       owner-question.sh asked <session>

Marks a session whose owner has asked a question. `record` reads each prompt.
`asked` exits 0 while the session is marked.
See ~/.claude/rules/develop_process_rules.md.
USAGE
  exit 64
}

mark_dir="${OWNER_QUESTION_DIR:-$HOME/.claude/owner-question}"

mark_for() {
  printf '%s/%s' "$mark_dir" "$(printf '%s' "$1" | shasum | cut -c1-40)"
}

is_machine_sent() {
  jq -e '(.prompt // "") | test("^\\s*<(task-notification|agent-message|cross-session-message|local-command-)")' <<< "$1" >/dev/null
}

is_question() {
  jq -e '
    (.prompt // "") | ascii_downcase
    | gsub("(?s)<pasted_content[^>]*>.*?</pasted_content[^>]*>"; "")
    | [splits("(?<=[.!?])\\s+|\\n+")] | map(select(test("\\S"))) | (last // "")
    | test("\\?[\\s\")*_]*$")
      or test("^\\s*(stop|wait|pause|hold on)\\b")
      or test("^((so|and|but|ok|okay|well|again|then|right|also|wait|hmm)[, ]+)*(what|whats|why|how|when|where|who|which|is|are|does|did)\\b")
  ' <<< "$1" >/dev/null
}

refuse() {
  jq -nc --arg text "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}'
}

case "${1:-}" in
  record)
    payload=$(cat)
    session=$(jq -r '.session_id // empty' <<< "$payload")
    [ -n "$session" ] || exit 0
    is_machine_sent "$payload" && exit 0
    if ! is_question "$payload"; then
      rm -f "$(mark_for "$session")"
      exit 0
    fi
    mkdir -p "$mark_dir"
    printf 'asked\n' > "$(mark_for "$session")"
    ;;
  stop)
    session=$(jq -r '.session_id // empty')
    [ -f "$(mark_for "$session")" ] || exit 0
    printf 'answered\n' > "$(mark_for "$session")"
    ;;
  check)
    payload=$(cat)
    session=$(jq -r '.session_id // empty' <<< "$payload")
    [ -f "$(mark_for "$session")" ] || exit 0
    if [ "$(cat "$(mark_for "$session")")" = answered ]; then
      refuse "The owner asked a question and it has been answered. A background task finishing is not permission to continue. Run nothing and end this turn with no message until the owner's next prompt."
      exit 0
    fi
    case "$(jq -r '.tool_name // empty' <<< "$payload")" in
      Read|Grep|Glob|LSP|ToolSearch|WebFetch|WebSearch|AskUserQuestion) exit 0 ;;
    esac
    refuse "The owner asked a question. Answer it and stop, changing nothing, until the owner's next prompt."
    ;;
  asked)
    [ $# -eq 2 ] || usage
    [ -f "$(mark_for "$2")" ]
    ;;
  *) usage ;;
esac
