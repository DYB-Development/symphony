#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ask-model.sh <run name> <fallback model> <last line> <system prompt> < question

Asks a model one question, read from standard input, and prints its reply. The
model is the one the owner's agent models file names for the run, or the
fallback. The run is given no tools, no settings and no servers.
USAGE
  exit 64
}

[ $# -eq 4 ] || usage

name=$1
fallback=$2
system_prompt=$4

model="$("$(dirname "$0")/agent-model.sh" lookup "$name" "$fallback")"

claude -p --model "$model" --system-prompt "$system_prompt" --tools "" --setting-sources "" \
  --no-session-persistence --strict-mcp-config
