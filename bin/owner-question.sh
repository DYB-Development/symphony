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

is_question() {
  jq -e '(.prompt // "") | test("\\?[\\s\"')*_]*$")' <<< "$1" >/dev/null
}

case "${1:-}" in
  record)
    payload=$(cat)
    session=$(jq -r '.session_id // empty' <<< "$payload")
    [ -n "$session" ] || exit 0
    is_question "$payload" || exit 0
    mkdir -p "$mark_dir"
    printf 'asked\n' > "$(mark_for "$session")"
    ;;
  asked)
    [ $# -eq 2 ] || usage
    [ -f "$(mark_for "$2")" ]
    ;;
  *) usage ;;
esac
