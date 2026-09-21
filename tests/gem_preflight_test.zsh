#!/usr/bin/env zsh
# Tests for bin/gem-preflight.sh. Every case runs inside a throwaway git repo
# holding a fake gem, and rubygems.org is answered by a stub rather than reached.
#
# Usage: zsh tests/gem_preflight_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
PREFLIGHT="$SCRIPT_DIR/../bin/gem-preflight.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      expected: %s\n' "${(qqq)expected}"
    printf '      actual:   %s\n' "${(qqq)actual}"
  fi
}

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

# A git repo holding one gem whose published versions the stub decides.
new_gem() {
  local name="${1:-widget}" version="${2:-0.2.0}"
  REPO="$(mktemp -d "${TMPDIR:-/tmp}/gem_preflight_test.XXXXXX")"
  git -C "$REPO" init -q
  mkdir -p "$REPO/lib/$name"
  print -r -- "module ${(C)name}; VERSION = \"$version\"; end" > "$REPO/lib/$name/version.rb"
  cat > "$REPO/$name.gemspec" <<SPEC
require_relative "lib/$name/version"

Gem::Specification.new do |spec|
  spec.name     = "$name"
  spec.version  = ${(C)name}::VERSION
  spec.authors  = [ "someone" ]
  spec.summary  = "a gem"
  spec.files    = [ "lib/$name/version.rb" ]
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
end
SPEC
  print -r -- "pkg/" > "$REPO/.gitignore"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@e -c user.name=t commit -qm "gem"
  cd "$REPO"
}

drop_gem() {
  cd "$SCRIPT_DIR"
  rm -rf "$REPO"
}

# Answers the published-versions lookup with a curl that never leaves the machine.
published() {
  local versions="$1"
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/gem_preflight_stub.XXXXXX")"
  {
    print -r -- "#!/usr/bin/env bash"
    print -r -- "printf '%s' '$versions'"
  } > "$STUB_BIN/curl"
  chmod +x "$STUB_BIN/curl"
  path=("$STUB_BIN" $path)
}

# A curl that answers the way rubygems.org answers for a gem it has never seen.
published_none() {
  STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/gem_preflight_stub.XXXXXX")"
  {
    print -r -- "#!/usr/bin/env bash"
    print -r -- "exit 22"
  } > "$STUB_BIN/curl"
  chmod +x "$STUB_BIN/curl"
  path=("$STUB_BIN" $path)
}

drop_stub() {
  path=(${path:#$STUB_BIN})
  rm -rf "$STUB_BIN"
}

echo "gem-preflight.sh:"

new_gem widget 0.2.0
published '[{"number":"0.1.0"}]'
assert_contains "widget 0.2.0" "$("$PREFLIGHT" 2>&1)" "names the gem and the version it read from the gemspec"
drop_stub
drop_gem

new_gem widget 0.2.0
published '[{"number":"0.2.0"},{"number":"0.1.0"}]'
"$PREFLIGHT" >/dev/null 2>&1
assert_equals "3" "$?" "exits with the nothing-to-release code when the version is already published"
drop_stub
drop_gem

new_gem widget 0.1.0
published_none
"$PREFLIGHT" >/dev/null 2>&1
assert_equals "0" "$?" "releases a gem rubygems.org has never seen"
drop_stub
drop_gem

new_gem widget 0.2.0
published_none
git -c tag.gpgSign=false tag -m v0.2.0 v0.2.0
assert_contains "v0.2.0" "$("$PREFLIGHT" 2>&1)" "names the release tag that already exists"
drop_stub
drop_gem

new_gem widget 0.2.0
published_none
git -c tag.gpgSign=false tag -m v0.2.0 v0.2.0
print -r -- "" > .gitignore
assert_contains "Problems found (2)" "$("$PREFLIGHT" 2>&1)" "reports every problem in one run rather than the first"
drop_stub
drop_gem

new_gem widget 0.2.0
published_none
print -r -- "this is not ruby" > widget.gemspec
assert_contains "widget.gemspec" "$("$PREFLIGHT" 2>&1)" "names the gemspec it could not read"
drop_stub
drop_gem

new_gem widget 0.2.0
published_none
rm widget.gemspec
assert_contains "no gemspec" "$("$PREFLIGHT" 2>&1)" "says so when the directory holds no gemspec"
drop_stub
drop_gem

new_gem widget 0.2.0
published_none
GITHUB_OUTPUT="$REPO/outputs" "$PREFLIGHT" >/dev/null 2>&1
assert_equals "name=widget
version=0.2.0
release=true" "$(cat "$REPO/outputs")" "hands the name, the version and the decision to the workflow"
drop_stub
drop_gem

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
