#!/usr/bin/env zsh
# Tests for bin/up.sh. Every case runs against a throwaway Rails app cloned from
# a throwaway remote, with its setup and server scripts, and lsof, curl and open,
# replaced by stubs that record each run.
#
# Usage: zsh tests/up_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
UP="$SCRIPT_DIR/../bin/up.sh"

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

new_app() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/up_test.XXXXXX")"
  BASE="${BASE:A}"
  RUNS="$BASE/runs"
  touch "$RUNS"
  git init -q --bare -b main "$BASE/remote.git"
  git clone -q "$BASE/remote.git" "$BASE/app" 2>/dev/null
  APP="$BASE/app"
  mkdir -p "$APP/bin"
  printf '#!/usr/bin/env bash\necho "setup $*" >> "%s"\n' "$RUNS" > "$APP/bin/setup"
  printf '#!/usr/bin/env bash\necho "dev PORT=$PORT" >> "%s"\n' "$RUNS" > "$APP/bin/dev"
  chmod +x "$APP/bin/setup" "$APP/bin/dev"
  git -C "$APP" add bin
  git -C "$APP" commit -q -m init
  git -C "$APP" push -q origin main 2>/dev/null
  mkdir -p "$BASE/stubs"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BASE/stubs/lsof"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BASE/stubs/curl"
  printf '#!/usr/bin/env bash\necho "open $*" >> "%s"\n' "$RUNS" > "$BASE/stubs/open"
  chmod +x "$BASE/stubs/lsof" "$BASE/stubs/curl" "$BASE/stubs/open"
}

push_new_commit() {
  git clone -q "$BASE/remote.git" "$BASE/other" 2>/dev/null
  git -C "$BASE/other" commit -q --allow-empty -m newer
  git -C "$BASE/other" push -q origin main 2>/dev/null
  git -C "$BASE/other" rev-parse HEAD
}

run_up() {
  (cd "$1" && PATH="$BASE/stubs:$PATH" "$UP")
}

drop_app() {
  cd "$SCRIPT_DIR"
  rm -rf "$BASE"
}

echo "up.sh:"

new_app
NEWER="$(push_new_commit)"
run_up "$APP" >/dev/null 2>&1
assert_equals "$NEWER" "$(git -C "$APP" rev-parse HEAD)" \
  "pulls the latest commits of the checked-out branch in a main clone"
drop_app

new_app
git -C "$APP" worktree add -q -b feature "$BASE/app-feature"
git -C "$BASE/app-feature" branch -q --set-upstream-to=origin/main
BEFORE="$(git -C "$BASE/app-feature" rev-parse HEAD)"
push_new_commit >/dev/null
run_up "$BASE/app-feature" >/dev/null 2>&1
assert_equals "$BEFORE" "$(git -C "$BASE/app-feature" rev-parse HEAD)" \
  "does not pull in a linked worktree"
drop_app

new_app
rm -rf "$BASE/remote.git"
OUTPUT="$(run_up "$APP" 2>&1)"
assert_equals "1 the pull failed " "$? $(grep -o 'the pull failed' <<<"$OUTPUT") $(cat "$RUNS")" \
  "says the pull failed, exits non-zero and neither sets up nor starts the app when the pull fails"
drop_app

new_app
run_up "$APP" >/dev/null 2>&1
assert_equals "setup --skip-server" "$(sed -n 1p "$RUNS")" \
  "runs the app's own setup step, without its server, before anything is started"
drop_app

new_app
printf '#!/usr/bin/env bash\ncase "$*" in *:3000*) exit 0 ;; esac\nexit 1\n' > "$BASE/stubs/lsof"
run_up "$APP" >/dev/null 2>&1
assert_equals "dev PORT=3001" "$(sed -n 2p "$RUNS")" \
  "starts the app's server on the first free port counting up from 3000"
drop_app

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
