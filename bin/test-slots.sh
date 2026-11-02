#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: test-slots.sh run <command> [<argument>...]
       test-slots.sh wrap

run runs a test command with PARALLEL_WORKERS set to the slots it takes from
the machine's shared total. wrap is the hook that rewrites an agent's Rails
test command to run that way.
USAGE
  exit 64
}

total="${TEST_SLOTS_TOTAL:-$(getconf _NPROCESSORS_ONLN)}"
ledger="${TEST_SLOTS_DIR:-$HOME/.claude/test-slots}"
leases="$ledger/leases"

started_at() {
  local started
  started=$(ps -o lstart= -p "$1" 2>/dev/null) || return 0
  echo $started
}

held_slots() {
  local file pid started slots held=0
  for file in "$leases"/*; do
    [ -f "$file" ] || continue
    { read -r pid; read -r started; read -r slots; } < "$file"
    [ "$(started_at "$pid")" = "$started" ] && held=$((held + slots))
  done
  echo "$held"
}

take_slots() {
  local holder=$1 free
  free=$((total - $(held_slots)))
  [ "$free" -ge 2 ] || free=2
  printf '%s\n%s\n%s\n' "$holder" "$(started_at "$holder")" "$free" > "$leases/$holder"
  echo "$free"
}

run() {
  local slots
  mkdir -p "$leases"
  slots=$(lockf -k "$ledger/lock" "$0" take $$)
  echo "Running tests with $slots workers"
  PARALLEL_WORKERS="$slots" exec "$@"
}

slots_command() {
  printf '%q' "$(cd "$(dirname "$0")" && pwd)/test-slots.sh"
}

plain_text='[^;&|<>`$()]*'
folder='[^;&|<>`$() ]+'
setting='[A-Za-z_][A-Za-z0-9_]*=[^;&|<>`$() ]*'
test_command="^((cd $folder && )*($setting )*)((bin/rails test(:all|:system)?|bin/ci)( $plain_text)?)\$"

wrap() {
  local input command
  input=$(cat)
  command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
  [[ "$command" =~ $test_command ]] || return 0
  printf '%s' "$input" | jq -c --arg command "${BASH_REMATCH[1]}$(slots_command) run ${BASH_REMATCH[4]}" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: (.tool_input + {command: $command})}}'
}

case "${1:-}" in
  run) shift; [ $# -ge 1 ] || usage; run "$@" ;;
  wrap) wrap ;;
  take) [ $# -eq 2 ] || usage; take_slots "$2" ;;
  *) usage ;;
esac
