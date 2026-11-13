#!/usr/bin/env bash
set -euo pipefail
set -f

usage() {
  cat >&2 <<'USAGE'
usage: full-suite-gate.sh check < hook.json

Refuses a subagent's run of a project's whole test suite. A subagent runs only
the test file of its current test-first cycle, and the main session runs the
whole suite before it creates the pull request.
See ~/.claude/rules/develop_process_rules.md.
USAGE
  exit 64
}

reason="A subagent runs only the test file it is working in, never the whole suite. Run that one file, or one test in it, and leave the full suite to the main session, which runs it before creating the pull request."

words_of() {
  local word words=()
  for word in $1; do
    case "$word" in
      [A-Za-z_]*=*) [ ${#words[@]} -eq 0 ] && continue ;;
      *'>'*|*'<'*) continue ;;
    esac
    words+=("$word")
  done
  printf '%s\n' "${words[*]:-}"
}

only_flags() {
  local word
  for word in "$@"; do
    case "$word" in
      -n|--name|-n=*|--name=*) return 1 ;;
      -*|[0-9]*) ;;
      *) return 1 ;;
    esac
  done
}

is_full_suite() {
  # shellcheck disable=SC2086
  set -- $1
  [ "${1:-}" = bundle ] && [ "${2:-}" = exec ] && shift 2
  case "${1:-}" in
    bin/ci) return 0 ;;
    bin/rails|rails)
      case "${2:-}" in test|test:all|test:system) shift 2; only_flags "$@" ;; *) return 1 ;; esac ;;
    rake)
      shift
      case "${1:-}" in test|spec|default) shift ;; -*|'') ;; *) return 1 ;; esac
      only_flags "$@" ;;
    rspec|*/run_tests.sh|run_tests.sh) shift; only_flags "$@" ;;
    bun|npm|yarn|pnpm)
      case "${2:-} ${3:-}" in
        'test '*) shift 2; only_flags "$@" ;;
        'run test'|'run test:'*) shift 3; only_flags "$@" ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

runs_full_suite() {
  local segment
  while IFS= read -r segment; do
    is_full_suite "$(words_of "$segment")" && return 0
  done < <(printf '%s\n' "$1" | sed -E 's/[0-9]*>&[0-9]+//g; s/(&&|\|\||[;|&])/\n/g')
  return 1
}

check() {
  local payload command
  payload=$(cat)
  [ -n "$(jq -r '.agent_id // empty' <<< "$payload")" ] || return 0
  command=$(jq -r '.tool_input.command // empty' <<< "$payload")
  runs_full_suite "$command" || return 0
  jq -nc --arg text "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}'
}

case "${1:-}" in
  check) check ;;
  *) usage ;;
esac
