#!/usr/bin/env bash
# Read the gem in the current directory and report everything that would stop
# it from being released.
#
# Usage: gem-preflight.sh
#
# Exit codes: 0 ready to release · 3 nothing to release · 1 problems found
set -uo pipefail

NOTHING_TO_RELEASE=3

gemspec_path() {
  local found=( *.gemspec )
  [[ -f "${found[0]:-}" ]] && printf '%s' "${found[0]}"
}

read_spec() {
  ruby -e '
    spec = Gem::Specification.load(ARGV[0])
    abort "unreadable" if spec.nil?
    puts spec.name
    puts spec.version
  ' "$1"
}

published_versions() {
  local name="$1" body
  body="$(curl -sS -f "https://rubygems.org/api/v1/versions/${name}.json")" || return 0
  printf '%s' "$body" | ruby -rjson -e 'puts JSON.parse($stdin.read).map { |v| v["number"] }' 2>/dev/null
}

main() {
  local spec_path
  spec_path="$(gemspec_path)"

  local spec_fields
  spec_fields="$(read_spec "$spec_path" 2>&1)" || return 1

  local name version
  name="$(printf '%s\n' "$spec_fields" | sed -n '1p')"
  version="$(printf '%s\n' "$spec_fields" | sed -n '2p')"

  printf '%s %s\n' "$name" "$version"

  if printf '%s\n' "$(published_versions "$name")" | grep -qxF "$version"; then
    printf 'Nothing to release: %s is already on rubygems.org.\n' "$version"
    return "$NOTHING_TO_RELEASE"
  fi
}

main "$@"
