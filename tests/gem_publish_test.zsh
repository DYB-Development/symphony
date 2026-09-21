#!/usr/bin/env zsh
# Tests for bin/gem-publish.sh. Every case runs inside a throwaway git repo with
# a real bare remote, and a gem command that records what it was asked to do
# instead of reaching rubygems.org.
#
# Usage: zsh tests/gem_publish_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
PUBLISH="$SCRIPT_DIR/../bin/gem-publish.sh"

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

# A gem repository with a real remote, so a tag push is really pushed.
new_gem() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/gem_publish.XXXXXX")"
  REMOTE="$WORK/origin.git"
  REPO="$WORK/widget"
  git init -q --bare "$REMOTE"
  git init -q "$REPO"
  mkdir -p "$REPO/lib/widget"
  print -r -- 'module Widget; VERSION = "0.2.0"; end' > "$REPO/lib/widget/version.rb"
  print -r -- 'Gem::Specification.new { |s| s.name = "widget" }' > "$REPO/widget.gemspec"
  print -r -- "pkg/" > "$REPO/.gitignore"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@e -c user.name=t commit -qm gem
  git -C "$REPO" remote add origin "$REMOTE"
  git -C "$REPO" push -q origin HEAD:refs/heads/main
  git -C "$REPO" config user.email t@e
  git -C "$REPO" config user.name t
  cd "$REPO"
}

drop_gem() {
  cd "$SCRIPT_DIR"
  rm -rf "$WORK"
}

# A gem command that writes down every call. PUSH_FAILS makes the upload fail.
stub_gem() {
  STUB_BIN="$WORK/bin"
  mkdir -p "$STUB_BIN"
  GEM_LOG="$WORK/gem-calls"
  : > "$GEM_LOG"
  cat > "$STUB_BIN/gem" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GEM_LOG"
case "$1" in
  build)
    out="${!#}"
    mkdir -p "$(dirname "$out")"
    : > "$out"
    ;;
  push)
    if [ -n "${PUSH_FAILS:-}" ]; then
      echo "rubygems.org rejected the gem" >&2
      exit 1
    fi
    ;;
esac
exit 0
STUB
  chmod +x "$STUB_BIN/gem"
  export GEM_LOG
  path=("$STUB_BIN" $path)
}

drop_stub() {
  path=(${path:#$STUB_BIN})
}

echo "gem-publish.sh:"

new_gem
stub_gem
"$PUBLISH" widget 0.2.0 >/dev/null 2>&1
assert_contains "build widget.gemspec" "$(cat "$GEM_LOG")" "builds the gem from the gemspec"
drop_stub
drop_gem

new_gem
stub_gem
"$PUBLISH" widget 0.2.0 >/dev/null 2>&1
assert_contains "push pkg/widget-0.2.0.gem" "$(cat "$GEM_LOG")" "pushes the package it built"
drop_stub
drop_gem

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
