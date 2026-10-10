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

STUBS="$(mktemp -d "${TMPDIR:-/tmp}/up_test_stubs.XXXXXX")"
STUBS="${STUBS:A}"
mkdir -p "$STUBS/path"
cat > "$STUBS/stub" <<'STUB'
#!/usr/bin/env bash
state="$UP_TEST_STATE"
case "${0##*/}" in
  lsof) grep -qx -- "$2" "$state/busy" 2>/dev/null ;;
  curl) exit "$(cat "$state/curl" 2>/dev/null || echo 0)" ;;
  open) echo "open $*" >> "$state/runs"; exit "$(cat "$state/open" 2>/dev/null || echo 0)" ;;
  setup) echo "setup $*" >> "$state/runs" ;;
  dev)
    [ -f "$state/serve" ] && { echo $$ > "$state/server.pid"; exec sleep 300; }
    echo "dev PORT=$PORT" >> "$state/runs" ;;
esac
STUB
chmod +x "$STUBS/stub"
for name in lsof curl open; do ln -s "$STUBS/stub" "$STUBS/path/$name"; done
ln -s "$STUBS/stub" "$STUBS/setup"
ln -s "$STUBS/stub" "$STUBS/dev"
UP_TEST_STATE=/nonexistent "$STUBS/stub" >/dev/null 2>&1

TEMPLATE="$STUBS/template"
git init -q --bare --template= -b main "$TEMPLATE/remote.git"
git clone -q --template= "$TEMPLATE/remote.git" "$TEMPLATE/app" 2>/dev/null
mkdir -p "$TEMPLATE/app/bin"
ln -s "$STUBS/setup" "$TEMPLATE/app/bin/setup"
ln -s "$STUBS/dev" "$TEMPLATE/app/bin/dev"
git -C "$TEMPLATE/app" add bin
git -C "$TEMPLATE/app" commit -q -m init
git -C "$TEMPLATE/app" push -q origin main 2>/dev/null
git clone -q "$TEMPLATE/remote.git" "$STUBS/other" 2>/dev/null
git -C "$STUBS/other" commit -q --allow-empty -m newer
git -C "$STUBS/other" push -q origin main:newer 2>/dev/null

new_app() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/up_test.XXXXXX")"
  BASE="${BASE:A}"
  export UP_TEST_STATE="$BASE"
  RUNS="$BASE/runs"
  touch "$RUNS"
  cp -R "$TEMPLATE/remote.git" "$TEMPLATE/app" "$BASE/"
  APP="$BASE/app"
  git -C "$APP" remote set-url origin "$BASE/remote.git"
}

push_new_commit() {
  git -C "$BASE/remote.git" update-ref refs/heads/main refs/heads/newer
  git -C "$BASE/remote.git" rev-parse main
}

run_up() {
  (cd "$1" && PATH="$STUBS/path:$PATH" "$UP")
}

drop_app() {
  cd "$SCRIPT_DIR"
  rm -rf "$BASE"
}

serve_until_killed() {
  SERVER_PID_FILE="$BASE/server.pid"
  touch "$BASE/serve"
}

start_up_in_own_group() {
  (cd "$1" && PATH="$STUBS/path:$PATH" exec perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' "$UP") >/dev/null 2>&1 &
  UP_PID=$!
}

poll() {
  local tries=100
  until eval "$1"; do
    (( --tries > 0 )) || return 1
    sleep 0.05
  done
}

server_stopped() {
  ! kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null
}

stop_leftover_server() {
  [[ -s "$SERVER_PID_FILE" ]] && kill -9 "$(cat "$SERVER_PID_FILE")" 2>/dev/null
  kill -9 "$UP_PID" 2>/dev/null
  return 0
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
echo "-iTCP:3000" > "$BASE/busy"
run_up "$APP" >/dev/null 2>&1
assert_equals "dev PORT=3001" "$(grep '^dev' "$RUNS")" \
  "starts the app's server on the first free port counting up from 3000"
drop_app

new_app
run_up "$APP" >/dev/null 2>&1
assert_equals "open http://localhost:3000" "$(grep '^open' "$RUNS")" \
  "opens the browser at the server's address once the server answers"
drop_app

new_app
echo 7 > "$BASE/curl"
OUTPUT="$(run_up "$APP" 2>&1)"
assert_equals "1 the server stopped before it answered " "$? $(grep -o 'the server stopped before it answered' <<<"$OUTPUT") $(grep '^open' "$RUNS")" \
  "says the server stopped, exits non-zero and opens no browser when the server stops before it answers"
drop_app

new_app
BEFORE="$(git -C "$APP" rev-parse HEAD)"
push_new_commit >/dev/null
rm "$APP/bin/setup" "$APP/bin/dev"
OUTPUT="$(run_up "$APP" 2>&1)"
assert_equals "65 no app up knows how to start $BEFORE " "$? $(grep -o 'no app up knows how to start' <<<"$OUTPUT") $(git -C "$APP" rev-parse HEAD) $(cat "$RUNS")" \
  "says there is no app it knows how to start, exits non-zero and changes nothing in a folder without one"
drop_app

new_app
serve_until_killed
start_up_in_own_group "$APP"
poll 'grep -q "^open" "$RUNS" && [[ -s "$SERVER_PID_FILE" ]]'
kill -INT -- -"$UP_PID"
poll '! kill -0 "$UP_PID" 2>/dev/null'
poll server_stopped
assert_equals "0" "$?" "stops the server it started when it is stopped with Ctrl-C"
stop_leftover_server
drop_app

new_app
serve_until_killed
echo 1 > "$BASE/open"
start_up_in_own_group "$APP"
poll '[[ -s "$SERVER_PID_FILE" ]]'
poll '! kill -0 "$UP_PID" 2>/dev/null'
poll server_stopped
assert_equals "0" "$?" "stops the server it started when it exits for any other reason"
stop_leftover_server
drop_app

rm -rf "$STUBS"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
