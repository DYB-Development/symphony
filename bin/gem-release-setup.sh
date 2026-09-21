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

reusable_workflow() {
  sed -n 's|.*uses: *\([^@]*\)@.*|\1|p' "$TEMPLATE"
}

gem_name() {
  local found=( *.gemspec )
  basename "${found[0]}" .gemspec
}

gem_repository() {
  git remote get-url origin | sed -e 's|.*github.com[:/]||' -e 's|\.git$||'
}

print_publisher() {
  local workflow gem repository
  workflow="$(reusable_workflow)"
  gem="$(gem_name)"
  repository="$(gem_repository)"

  local workflow_owner="${workflow%%/*}"
  local workflow_repository="${workflow#*/}"
  workflow_repository="${workflow_repository%%/*}"

  printf '\nRegister the trusted publisher at\n'
  printf '  https://rubygems.org/gems/%s/trusted_publishers/new\n\n' "$gem"
  printf '  %-26s %s\n' "Repository owner" "${repository%%/*}"
  printf '  %-26s %s\n' "Repository name" "${repository##*/}"
  printf '  %-26s %s\n' "Workflow filename" "${workflow##*/}"
  printf '  %-26s %s\n' "Environment" "leave blank"
  printf '  %-26s %s\n' "Workflow repository owner" "$workflow_owner"
  printf '  %-26s %s\n' "Workflow repository name" "$workflow_repository"
}

install_caller
print_publisher
