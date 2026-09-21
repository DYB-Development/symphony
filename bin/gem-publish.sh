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

push() {
  printf 'Pushing %s to rubygems.org\n' "$PACKAGE"
  gem push "$PACKAGE"
}

tag() {
  local name="v$VERSION"

  if git rev-parse -q --verify "refs/tags/$name" >/dev/null; then
    printf 'The tag %s is already here\n' "$name"
  else
    printf 'Tagging %s\n' "$name"
    git tag -m "$name" "$name" || return 1
  fi

  git push origin "refs/tags/$name"
}

build || exit 1
push || exit 1

tag || {
  printf '%s %s is on rubygems.org but the tag did not reach the remote\n' "$GEM" "$VERSION" >&2
  exit 1
}
