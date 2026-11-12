#!/usr/bin/env bash
set -euo pipefail

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

runs_full_suite() {
  [ "$1" = "bin/rails test" ]
}

check() {
  local payload command
  payload=$(cat)
  command=$(jq -r '.tool_input.command // empty' <<< "$payload")
  runs_full_suite "$command" || return 0
  jq -nc --arg text "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}'
}

case "${1:-}" in
  check) check ;;
  *) usage ;;
esac
