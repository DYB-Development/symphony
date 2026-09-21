#!/usr/bin/env bash
# Read the gem in the current directory and report everything that would stop
# it from being released. Every check runs, so one run names every problem.
#
# Usage: gem-preflight.sh
#
# Exit codes: 0 ready to release · 3 nothing to release · 1 problems found
set -uo pipefail

NOTHING_TO_RELEASE=3

FINDINGS=()

finding() {
  FINDINGS+=("$1")
}

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

check_tag_is_free() {
  local tag="v$1"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null || return 0
  finding "The tag $tag already exists but that version is not on rubygems.org, so an earlier release tagged the commit and then failed to push the gem. Delete the tag or raise the version."
}

check_built_gem_is_ignored() {
  local built="pkg/$1-$2.gem"
  git check-ignore -q "$built" && return 0
  finding "Git does not ignore $built, so the release will build the gem and then refuse to go on because the working tree is dirty. Add pkg/ to .gitignore."
}

report() {
  [[ ${#FINDINGS[@]} -eq 0 ]] && return 0

  printf '\nProblems found (%d):\n\n' "${#FINDINGS[@]}"
  printf -- '- %s\n' "${FINDINGS[@]}"
  return 1
}

main() {
  local spec_path
  spec_path="$(gemspec_path)"

  local spec_fields
  if ! spec_fields="$(read_spec "$spec_path" 2>&1)"; then
    finding "Ruby could not read $spec_path, so nothing else could be checked: ${spec_fields}. Fix the gemspec and push again."
    report
    return 1
  fi

  local name version
  name="$(printf '%s\n' "$spec_fields" | sed -n '1p')"
  version="$(printf '%s\n' "$spec_fields" | sed -n '2p')"

  printf '%s %s\n' "$name" "$version"

  if printf '%s\n' "$(published_versions "$name")" | grep -qxF "$version"; then
    printf 'Nothing to release: %s is already on rubygems.org.\n' "$version"
    return "$NOTHING_TO_RELEASE"
  fi

  check_tag_is_free "$version"
  check_built_gem_is_ignored "$name" "$version"

  report
}

main "$@"
