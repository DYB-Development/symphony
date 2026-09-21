#!/usr/bin/env zsh
# Tests for bin/gem-release-setup.sh. Every case runs inside a throwaway clone
# of a fake gem, so no real repository is written to.
#
# Usage: zsh tests/gem_release_setup_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SETUP="$SCRIPT_DIR/../bin/gem-release-setup.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

new_gem() {
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/gem_release_setup.XXXXXX")"
  git -C "$REPO" init -q
  git -C "$REPO" remote add origin "git@github.com:acme/widget.git"
  mkdir -p "$REPO/lib/widget"
  print -r -- 'module Widget; VERSION = "0.2.0"; end' > "$REPO/lib/widget/version.rb"
  cat > "$REPO/widget.gemspec" <<'SPEC'
require_relative "lib/widget/version"

Gem::Specification.new do |spec|
  spec.name    = "widget"
  spec.version = Widget::VERSION
  spec.authors = [ "someone" ]
  spec.summary = "a gem"
  spec.files   = [ "lib/widget/version.rb" ]
end
SPEC
  cd "$REPO"
}

drop_gem() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
}

echo "gem-release-setup.sh:"

new_gem
"$SETUP" >/dev/null 2>&1
assert_contains "DYB-Development/symphony/.github/workflows/gem-release.yml" \
  "$(cat "$REPO/.github/workflows/release.yml" 2>/dev/null)" \
  "writes the caller workflow into the gem"
drop_gem

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
