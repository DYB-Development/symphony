#!/usr/bin/env bash
# Read the gem in the current directory and report everything that would stop
# it from being released.
#
# Usage: gem-preflight.sh
set -uo pipefail

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

main() {
  local spec_path
  spec_path="$(gemspec_path)"

  local spec_fields
  spec_fields="$(read_spec "$spec_path" 2>&1)" || return 1

  local name version
  name="$(printf '%s\n' "$spec_fields" | sed -n '1p')"
  version="$(printf '%s\n' "$spec_fields" | sed -n '2p')"

  printf '%s %s\n' "$name" "$version"
}

main "$@"
