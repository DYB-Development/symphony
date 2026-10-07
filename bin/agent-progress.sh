#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: agent-progress.sh
       agent-progress.sh record < hook.json
       agent-progress.sh line <session>

Shows each running subagent's target, the step it is on, how long it has been on
that step and how long it has run. `line` prints, for each running subagent of
one session, its type and target above a bar of how far through its numbered
steps it is, for the status line. `record` is the hook: it appends a line to
the subagent's log when it marks a step with scribe-step.sh, when it runs a
script from ~/.claude/bin, and when it stops.
Logs are kept in ~/.claude/agent-progress, one file per subagent.
USAGE
  exit 64
}

log_dir="${AGENT_PROGRESS_DIR:-$HOME/.claude/agent-progress}"
agents_dir="${AGENT_PROGRESS_AGENTS:-$(dirname "$0")/../agents}"
now="${AGENT_PROGRESS_NOW:-$(date +%s)}"

position_for() {
  printf '%s' "$1" | sed -nE 's/.*scribe-step\.sh[[:space:]]+"[^"]*"[[:space:]]+"[^"]*"[[:space:]]+"([^"]*)".*/\1/p'
}

step_for() {
  local command=$1 marked script
  marked=$(printf '%s' "$command" | sed -nE 's/.*scribe-step\.sh[[:space:]]+"([^"]*)"[[:space:]]+"([^"]*)".*/\1	\2/p')
  if [ -n "$marked" ]; then
    printf '%s' "$marked"
    return
  fi
  script=$(printf '%s' "$command" | sed -nE 's/.*\.claude\/bin\/([A-Za-z0-9_-]+)\.sh.*/\1/p')
  [ -z "$script" ] || printf '\truns %s' "$script"
}

show_progress() {
  awk -F '\t' -v now="$now" '
    function duration(seconds) { return sprintf("%dm%02ds", int(seconds / 60), seconds % 60) }
    NR == 1 { started = $1 }
    $3 != "" { target = " " $3 }
    { type = $2; step = $4; at = $1 }
    END {
      if (step == "finished") exit
      printf "%s%s — %s — %s on this step, %s in all\n", type, target, step, duration(now - at), duration(now - started)
    }
  ' "$1"
}

recent_logs() {
  [ -d "$log_dir" ] || return 0
  find "$log_dir" -name '*.log' -mmin -60
}

latest_step() {
  awk -F '\t' '
    $3 != "" { target = $3 }
    $4 == "finished" { finished = 1 }
    $4 != "" && $4 != "finished" { last = $4 }
    $4 != "" && $4 != "finished" && $4 !~ /^runs / { step = $4; position = $6 }
    { type = $2; if ($5 != "") session = $5 }
    END { if (!finished) printf "%s\037%s\037%s\037%s\037%s\037%s\n", type, target, step, position, session, last }
  ' "$1"
}

bar() {
  local tenths=$1
  printf '%*s' "$tenths" '' | sed 's/ /█/g'
  printf '%*s' $(( 10 - tenths )) '' | sed 's/ /░/g'
}

show_line() {
  local type target step position session last n title total
  IFS=$'\037' read -r type target step position session last < <(latest_step "$2") || return 0
  [ "$session" = "$1" ] || return 0
  n=${step%%.*}
  title=${step#*. }
  total=$(grep -cE '^[0-9]+\. \*\*' "$agents_dir/$type.md" 2>/dev/null || true)
  if [[ ! "$n" =~ ^[0-9]+$ ]] || [ "${total:-0}" -eq 0 ]; then
    printf '%s%s · %s\n' "$type" "${target:+ $target}" "$last"
    return 0
  fi
  printf '%s%s\n' "$type" "${target:+ $target}"
  local k=0 of=1 fraction=${position%% *}
  if [[ "$fraction" =~ ^([0-9]+)/([0-9]+)$ ]]; then k=${BASH_REMATCH[1]}; of=${BASH_REMATCH[2]}; fi
  printf '%s %s/%s · %s%s\n' "$(bar $(( ((n - 1) * of + k) * 10 / (of * total) )))" "$n" "$total" "$title" "${position:+ · $position}"
}

case "${1:-}" in
  line)
    [ $# -eq 2 ] || usage
    recent_logs | while IFS= read -r log; do
      show_line "$2" "$log"
    done
    ;;
  record)
    payload=$(cat)
    agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty')
    [ -n "$agent_id" ] || exit 0
    agent_type=$(printf '%s' "$payload" | jq -r '.agent_type // empty')
    session=$(printf '%s' "$payload" | jq -r '.session_id // empty')
    if [ "$(printf '%s' "$payload" | jq -r '.hook_event_name // empty')" = SubagentStop ]; then
      step=$(printf '\tfinished')
    else
      command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
      step=$(step_for "$command")
      [ -n "$step" ] || exit 0
      position=$(position_for "$command")
    fi
    mkdir -p "$log_dir"
    printf '%s\t%s\t%s\t%s%s\n' "$now" "$agent_type" "$step" "$session" "${position:+$'\t'$position}" >> "$log_dir/$agent_id.log"
    ;;
  "")
    running=$(recent_logs | while IFS= read -r log; do
      show_progress "$log"
    done)
    printf '%s\n' "${running:-No agents running.}"
    ;;
  *) usage ;;
esac
