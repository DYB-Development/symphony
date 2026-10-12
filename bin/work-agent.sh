#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: work-agent.sh

Starts a pipeline agent step's pinned agent version as its own Claude Code
session. Run by pipeline.sh inside a clone of the work item's repo, with
WORK_ITEM_ID and PIPELINE_STEP, the step the hub named, set. It prints the
session's JSON result.
USAGE
  exit 64
}

[ -n "${WORK_ITEM_ID:-}" ] && [ -n "${PIPELINE_STEP:-}" ] || usage

tools=$(jq -r '.agent_version.tools | join(",")' <<<"$PIPELINE_STEP")

"${SYMPHONY_CLAUDE:-claude}" -p "$(jq -r '.work.title' <<<"$PIPELINE_STEP")" \
  --system-prompt "$(jq -r '.agent_version.instructions' <<<"$PIPELINE_STEP")" \
  --tools "$tools" --allowedTools "$tools"
