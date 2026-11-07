#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work.sh "<address>" "<label>"

Appends one piece of work to .work at the worktree root as a JSON line holding
its full address and a short label, creating the file if absent and recording
an address it already holds once. Taking an issue or a work item records it, and
a Jira ticket is recorded by calling this with its address.
The file is gitignored and is removed with the worktree when the branch's PR
merges. See ~/.claude/rules/agent-worktrees.md.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage

address=$1
label=$2

root=$(git rev-parse --show-toplevel) || {
  echo "work.sh: not inside a git repository" >&2
  exit 69
}

file="$root/.work"

[ -s "$file" ] && jq -se --arg address "$address" 'any(.address == $address)' "$file" >/dev/null && exit 0

jq -nc --arg address "$address" --arg label "$label" '{address: $address, label: $label}' >> "$file"
