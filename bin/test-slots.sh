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
runs="${TEST_RUNS_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/test-runs.tsv}"

started_at() {
  local started
  started=$(ps -o lstart= -p "$1" 2>/dev/null) || return 0
  echo $started
}

is_number() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

held_slots() {
  local file pid started slots held=0
  for file in "$leases"/*; do
    [ -f "$file" ] || continue
    pid="" started="" slots=""
    { read -r pid; read -r started; read -r slots; } < "$file" || true
    if is_number "$pid" && is_number "$slots" && [ -n "$started" ] && [ "$(started_at "$pid")" = "$started" ]; then
      held=$((held + slots))
    else
      rm -f "$file"
    fi
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
  local status=0
  mkdir -p "$leases" 2>/dev/null && slots=$(lockf -k -t 5 "$ledger/lock" "$0" take $$ 2>/dev/null) || status=$?
  case "$status" in
    0) echo "Running tests with $slots workers" ;;
    75) slots=2; echo "Running tests with $slots workers, since the slot ledger at $ledger stayed locked for 5 seconds" ;;
    *) slots=2; echo "Running tests with $slots workers, since the slot ledger at $ledger could not be used" ;;
  esac
  local began child
  began=$(date +%s)
  PARALLEL_WORKERS="$slots" "$@" <&0 &
  child=$!
  trap 'stopped=1; kill -TERM "$child" 2>/dev/null' TERM INT HUP
  [ "$status" != 0 ] || hand_lease_to "$child" "$slots"
  status=0
  wait "$child" || status=$?
  if [ -n "${stopped:-}" ]; then
    status=0
    wait "$child" || status=$?
  fi
  rm -f "$leases/$child" "$leases/$$" 2>/dev/null || true
  local outcome=$status
  [ -z "${stopped:-}" ] || outcome=interrupted
  ! is_full_suite "$@" || record_run "$slots" "$began" "$outcome"
  exit "$status"
}

hand_lease_to() {
  local child=$1 slots=$2 started
  started=$(started_at "$child")
  [ -n "$started" ] || return 0
  printf '%s\n%s\n%s\n' "$child" "$started" "$slots" > "$leases/$child"
  rm -f "$leases/$$"
}

is_full_suite() {
  case "$1" in
    bin/ci) return 0 ;;
    bin/rails) ;;
    *) return 1 ;;
  esac
  case "${2:-}" in test|test:all|test:system) ;; *) return 1 ;; esac
  shift 2
  local argument
  for argument in "$@"; do
    case "$argument" in -*) ;; *) return 1 ;; esac
  done
}

record_run() {
  local workers=$1 began=$2 status=$3 branch worktree
  branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo detached)
  worktree=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$branch" "$worktree" "$workers" \
    "$(date -u -r "$began" +%Y-%m-%dT%H:%M:%SZ)" "$(($(date +%s) - began))" "$status" >> "$runs"
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
