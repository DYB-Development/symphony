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

modified_at() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

is_marked() {
  local mark
  mark=$(mark_for "$1")
  [ -f "$mark" ] || return 1
  [ $(( $(date +%s) - $(modified_at "$mark") )) -le 86400 ]
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

reads_only_pattern='^ *(\[|test|true|read|ls|cat|head|tail|wc|pwd|grep|rg|which|stat|file|date|echo|printf|jq|basename|dirname|sort|uniq|cut|tr|diff|cd)( |$)|^ *sed +-n |^ *find ([^-]|-[^def])*$|^ *git( +-C +[^ ]+)? +(fetch|rev-list|ls-tree|cat-file|for-each-ref|status|log|diff|show|blame|ls-files|rev-parse|merge-base|describe|grep|shortlog|worktree +list|branch +--show-current|branch +--list|branch +-a|remote +-v|remote +get-url)( |$)|^ *gh +api( |$)|^ *gh +(issue|pr|run|repo|release) +(view|list|diff|checks|status)( |$)|^ *[^ ]*saved-answers\.sh( |$)'

without_quoted_text() {
  printf '%s' "$1" | sed "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g"
}

without_output_discards() {
  printf '%s' "$1" | sed -E 's/[0-9]*>&[0-9]+([ ;|&]|$)/ \1/g; s/(&|[0-9]*)>+ *\/dev\/null([ ;|&]|$)/ \2/g'
}

without_command_prefixes() {
  printf '%s' "$1" | sed -E -e 's/^ *for +[^ ]+ +in( .*)?$//' -e ':again' -e 's/^ *(do|done|if|then|elif|else|fi|while|xargs( +-[0-9A-Za-z]+( +[0-9{}%]+)?)*|g?timeout +[0-9]+[smhd]?|[A-Za-z_][A-Za-z0-9_]*=[^ ]*)( +|$)//' -e 't again'
}

gh_api_call_reads() {
  local without_get
  grep -Eq '^ *gh +api( |$)' <<< "$1" || return 0
  without_get=$(sed -E 's/ (-X|--method)[ =]?GET( |$)/ /g' <<< "$1")
  grep -Eq ' (-[A-Za-z]*X|--method)' <<< "$without_get" && return 1
  [ "$without_get" = "$1" ] || return 0
  ! grep -Eq ' (-[A-Za-z]*[fF]|--field|--raw-field|--input)' <<< "$1"
}

without_read_substitutions() {
  local command=$1 pattern='\$\(([^()]*)\)' substitution inner
  while [[ "$command" =~ $pattern ]]; do
    substitution=${BASH_REMATCH[0]}
    inner=${BASH_REMATCH[1]}
    only_reads "$inner" || return 1
    command=${command/"$substitution"/Q}
  done
  printf '%s' "$command"
}

only_reads() {
  local command plain segment
  command=$(without_read_substitutions "$1") || return 1
  case "$command" in *'$('*|*'`'*) return 1 ;; esac
  plain=$(without_output_discards "$(without_quoted_text "$command")")
  case "$plain" in *'>'*|*'<('*) return 1 ;; esac
  while IFS= read -r segment; do
    segment=$(without_command_prefixes "$segment")
    [ -n "${segment// /}" ] || continue
    printf '%s\n' "$segment" | grep -Eq "$reads_only_pattern" || return 1
    gh_api_call_reads "$segment" || return 1
  done < <(printf '%s\n' "$plain" | tr ';|&' '\n')
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
    [ "${CLAUDE_CODE_SESSION_ATTENDED:-1}" = 0 ] && exit 0
    rm -f "$(mark_for "$session").refusals"
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
    is_marked "$session" || exit 0
    [ -z "$(jq -r '.agent_id // empty' <<< "$payload")" ] || exit 0
    if [ "$(cat "$(mark_for "$session")")" = answered ]; then
      refuse "The owner asked a question and it has been answered. A background task finishing is not permission to continue. Run nothing and end this turn with no message until the owner's next prompt."
      exit 0
    fi
    case "$(jq -r '.tool_name // empty' <<< "$payload")" in
      Read|Grep|Glob|LSP|ToolSearch|WebFetch|WebSearch|AskUserQuestion) exit 0 ;;
      Bash) only_reads "$(jq -r '.tool_input.command // empty' <<< "$payload")" && exit 0 ;;
      Agent) case "$(jq -r '.tool_input.subagent_type // empty' <<< "$payload")" in Explore|claude-code-guide) exit 0 ;; esac ;;
    esac
    refuse "The owner asked a question, and this call was not recognised as read-only. Reads are still allowed, so look up what the answer needs with Read, Grep or a plain read command, then answer and stop, changing nothing, until the owner's next prompt."
    ;;
  path)
    [ $# -eq 2 ] || usage
    mark_for "$2"
    ;;
  asked)
    [ $# -eq 2 ] || usage
    is_marked "$2"
    ;;
  *) usage ;;
esac
