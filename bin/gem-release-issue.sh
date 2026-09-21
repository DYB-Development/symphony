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

open_issue_for_this_version() {
  gh issue list --state open --search "$TITLE in:title" --json number,title \
    | ruby -rjson -e '
        title = ARGV[0]
        match = JSON.parse($stdin.read).find { |issue| issue["title"] == title }
        print match ? match["number"] : ""
      ' "$TITLE"
}

LABEL="release-failure"

ensure_label() {
  gh label create "$LABEL" --color b60205 --description "A gem release that did not reach rubygems.org" >/dev/null 2>&1 || true
}

EXISTING="$(open_issue_for_this_version)"

if [[ -n "$EXISTING" ]]; then
  body | gh issue comment "$EXISTING" --body-file -
else
  ensure_label
  body | gh issue create --title "$TITLE" --body-file - --label "$LABEL"
fi
