#!/usr/bin/env bash
# Open an issue in the gem's own repository saying that a release failed, and
# read what went wrong from standard input.
#
# Usage: gem-release-issue.sh <gem> <version> < details
set -euo pipefail

GEM="${1:?gem name}"
VERSION="${2:?version}"

TITLE="Release failed: $GEM $VERSION"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

body() {
  printf '`%s` %s did not reach rubygems.org.\n\n' "$GEM" "$VERSION"
  printf 'Run: %s\n' "$RUN_URL"
  printf 'Commit: %s\n\n' "${GITHUB_SHA:-unknown}"
  printf '## What went wrong\n\n'
  cat
}

body | gh issue create --title "$TITLE" --body-file -
