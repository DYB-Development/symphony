#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: render-plan.sh <owner/repo> <issue-number>

Prints the page for a feature plan, built from the plan issue's title and body
in the one layout every plan page uses.
See ~/.claude/rules/feature-plan.md.
USAGE
  exit 64
}

[ $# -eq 2 ] || usage
