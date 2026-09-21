#!/usr/bin/env bash
# Build the gem in the current directory, push it to rubygems.org, and tag the
# commit it was built from.
#
# Usage: gem-publish.sh <gem> <version>
set -uo pipefail

GEM="${1:?gem name}"
VERSION="${2:?version}"

PACKAGE="pkg/$GEM-$VERSION.gem"

build() {
  printf 'Building %s\n' "$PACKAGE"
  gem build "$GEM.gemspec" --output "$PACKAGE"
}

build
