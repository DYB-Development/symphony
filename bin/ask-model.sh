#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ask-model.sh <run name> <fallback model> <last line> <system prompt> < question

Asks a model one question, read from standard input, and prints its reply. The
model is the one the owner's agent models file names for the run, or the
fallback. The run is given no tools, no settings and no servers. A run that
fails, or a reply whose last line does not match <last line> as an extended
regular expression, exits 70.
USAGE
  exit 64
}

[ $# -eq 4 ] || usage

name=$1
fallback=$2
last_line=$3
system_prompt=$4

model="$("$(dirname "$0")/agent-model.sh" lookup "$name" "$fallback")"

reply=$(claude -p --model "$model" --system-prompt "$system_prompt" --tools "" --setting-sources "" \
  --no-session-persistence --strict-mcp-config) ||
  { echo "ask-model.sh: the $name run failed" >&2; exit 70; }
printf '%s\n' "$reply"

printf '%s\n' "$reply" | awk 'NF { last = $0 } END { print last }' | grep -qxE -- "$last_line" ||
  { echo "ask-model.sh: the $name reply does not end with the line the run expects" >&2; exit 70; }
