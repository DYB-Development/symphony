#!/usr/bin/env zsh
# Tests for bin/lessons-hook.sh, the SessionStart hook that adds a repo's
# lessons file, kept outside the repo, to the session's context.
#
# Usage: zsh tests/lessons_hook_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
HOOK="$SCRIPT_DIR/../bin/lessons-hook.sh"

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

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/lessons_hook.XXXXXX")"
SANDBOX="${SANDBOX:A}"
trap 'rm -rf "$SANDBOX"' EXIT

export SYMPHONY_LESSONS_DIR="$SANDBOX/lessons"
mkdir -p "$SYMPHONY_LESSONS_DIR"

CLONE="$SANDBOX/shop"
git init -q -b main "$CLONE"
git -C "$CLONE" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

run_hook() { jq -nc --arg cwd "$1" '{hook_event_name: "SessionStart", cwd: $cwd}' | "$HOOK"; }
context_from() { run_hook "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

echo "lessons-hook.sh:"

printf '# Lessons\n\n## This repo\n- Build each form on its own page.\n' > "$SYMPHONY_LESSONS_DIR/shop.md"

assert_contains \
  "Build each form on its own page." \
  "$(context_from "$CLONE")" \
  "adds the repo's lessons file to the context when the session starts in the main clone"

WORKTREE="$SANDBOX/shop-feature-quotes"
git -C "$CLONE" worktree add -q -b feature/quotes "$WORKTREE"

assert_contains \
  "Build each form on its own page." \
  "$(context_from "$WORKTREE")" \
  "adds the main clone's lessons file when the session starts in a linked worktree of it"

assert_contains \
  "$SYMPHONY_LESSONS_DIR/shop.md" \
  "$(context_from "$WORKTREE")" \
  "names the path the lessons file lives at, so a session knows where to write a new lesson"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
