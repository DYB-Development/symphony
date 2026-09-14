#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: scribe-step.sh "<target>" "<step>"

Marks the step a scribe is starting. It prints the target and the step and
writes nothing: the progress hook sees the call and records it against the
agent that made it, so `agent-progress.sh` can show which step each running
agent is on.
See ~/.claude/bin/agent-progress.sh.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

printf '%s · %s\n' "$1" "$2"
