#!/usr/bin/env bash
# Wire one gem repository to the shared release workflow and print the trusted
# publisher to register for it on rubygems.org.
#
# Usage: gem-release-setup.sh [gem-repo-path]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/../templates/gem-release-caller.yml"

REPO="${1:-.}"
cd "$REPO"

install_caller() {
  mkdir -p .github/workflows
  cp "$TEMPLATE" .github/workflows/release.yml
  printf 'Wrote .github/workflows/release.yml\n'
}

install_caller
