#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: owner-turn.sh "<kind>" "<what is wanted>" ["<link>"]

Marks an item the owner is waited on for. The kind is one of permission,
question, pull request or plan. It prints the entry and writes nothing: the
owner's turn hook sees the call and records it against the session that made it.
USAGE
  exit 64
}

kinds="permission, question, pull request or plan"

valid_kind() {
  case "$1" in permission|question|"pull request"|plan) return 0 ;; *) return 1 ;; esac
}

[ $# -ge 2 ] && [ $# -le 3 ] || usage

valid_kind "$1" || {
  printf 'owner-turn.sh: the kind is one of %s\n' "$kinds" >&2
  exit 64
}
