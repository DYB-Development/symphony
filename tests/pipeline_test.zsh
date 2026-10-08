#!/usr/bin/env zsh
# Tests for bin/pipeline.sh. Every case runs against a stub curl that answers
# each hub method from files the case writes and records each call, a stub gh,
# a throwaway settings folder and a throwaway git repo, so nothing reaches
# dyb_web or GitHub.
#
# Usage: zsh tests/pipeline_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
PIPELINE="$SCRIPT_DIR/../bin/pipeline.sh"

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

setup() {
  WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pipeline_test.XXXXXX")" && pwd -P)"
  mkdir -p "$WORK/bin" "$WORK/answers" "$WORK/settings" "$WORK/repo"
  printf 'url=https://dyb.example\ntoken=secret\n' > "$WORK/settings/dyb_web"
  export SYMPHONY_CONFIG_DIR="$WORK/settings" SYMPHONY_SESSION="session-a"
  cat > "$WORK/bin/curl" <<STUB
#!/usr/bin/env bash
[ -z "\${STUB_CURL_DOWN:-}" ] || exit 7
url="" data="" method=GET
while [ \$# -gt 0 ]; do
  case "\$1" in
    -X) method="\$2"; shift ;;
    -d|--data) data="\$2"; method=POST; shift ;;
    http*) url="\$1" ;;
  esac
  shift
done
name="\${url##*/}"; name="\${name%%\\?*}"
printf '%s %s %s\\n' "\$method" "\$name" "\$data" >> "$WORK/calls"
count=\$(( \$(cat "$WORK/count.\$name" 2>/dev/null || echo 0) + 1 ))
echo "\$count" > "$WORK/count.\$name"
answer="$WORK/answers/\$name.\$count"
[ -f "\$answer" ] || answer="$WORK/answers/\$name"
printf '%s\\n%s' "\$(cat "\$answer" 2>/dev/null || echo '{"answer":null}')" "\$(cat "$WORK/answers/\$name.code" 2>/dev/null || echo 200)"
STUB
  chmod +x "$WORK/bin/curl"
  path=("$WORK/bin" $path)
  git -C "$WORK/repo" init -q
  cd "$WORK/repo"
}

teardown() {
  cd "$SCRIPT_DIR"
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
  unset SYMPHONY_CONFIG_DIR SYMPHONY_SESSION STUB_CURL_DOWN SYMPHONY_STEP_DIR
}

step_script() {
  mkdir -p "$WORK/steps"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$WORK/steps/$1.sh"
  chmod +x "$WORK/steps/$1.sh"
  export SYMPHONY_STEP_DIR="$WORK/steps"
}

report() { grep '^POST report_step ' "$WORK/calls" | sed -n "${1:-1}p" | cut -d' ' -f3- | jq -c "$2"; }

calls() { cut -d' ' -f1,2 "$WORK/calls" | tr '\n' ',' | sed 's/,$//'; }

work_branch() {
  git -C "$WORK/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m start
  git -C "$WORK/repo" branch "$1"
}

pull_request() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/gh_calls"\nprintf %%s %s\n' "$WORK" "${(q)1}" > "$WORK/bin/gh"
  chmod +x "$WORK/bin/gh"
}

answer() { printf '%s' "$2" > "$WORK/answers/$1"; }

step() {
  jq -nc --arg id "$1" --arg name "$2" --arg kind "$3" --arg script "${4:-}" \
    '{answer: {id: $id, name: $name, kind: $kind, script: $script, agent: "builder", model: "claude-sonnet-5-5",
      work: {title: "Export quotes", request: "Reps want quotes as CSV", acceptance_criteria: "A rep downloads a CSV", repo: "acme/quotes"}}}'
}

setup
answer claim_work_item '{"answer":7}'
answer current_step "$(step check "Run work-check" script work-check)"
assert_equals "Claimed Export quotes
First step: Run work-check" "$("$PIPELINE" claim 7)" "claiming a work item by its id prints its title and its first step"
teardown

setup
export STUB_CURL_DOWN=1
assert_equals "dyb_web cannot be reached at https://dyb.example" "$("$PIPELINE" claim 7 2>&1)" "says dyb_web cannot be reached and runs nothing"
teardown

setup
answer claim_work_item.code 401
assert_equals "dyb_web refused the token" "$("$PIPELINE" claim 7 2>&1)" "says dyb_web refused the token and runs nothing"
teardown

setup
step_script work-check 'echo "12 runs, 0 failures"'
answer current_step.1 "$(step check "Run work-check" script work-check)"
answer current_step '{"answer":{"done":true,"output":"stopped"}}'
"$PIPELINE" run 7 >/dev/null 2>&1
assert_equals "GET current_step,POST start_step,POST report_step,GET current_step" "$(calls)" "tells the hub a script step has started before it runs"
teardown

setup
step_script work-check 'echo "12 runs, 0 failures"'
answer current_step.1 "$(step check "Run work-check" script work-check)"
answer current_step '{"answer":{"done":true,"output":"stopped"}}'
"$PIPELINE" run 7 >/dev/null 2>&1
assert_equals '{"step":"check","result":"passed","exit_status":0,"output":"12 runs, 0 failures"}' "$(report 1 '{step, result, exit_status, output}')" "reports a script step's exit status and output"
teardown

setup
step_script work-check 'echo "2 failures"; exit 3'
answer current_step.1 "$(step check "Run work-check" script work-check)"
answer current_step '{"answer":{"done":true,"output":"stopped"}}'
"$PIPELINE" run 7 >/dev/null 2>&1
assert_equals '{"result":"failed","exit_status":3}' "$(report 1 '{result, exit_status}')" "reports a step whose script exits non-zero as failed, with its exit status"
teardown

setup
step_script work-check 'echo checked'
step_script work-push 'echo pushed'
answer current_step.1 "$(step check "Run work-check" script work-check)"
answer current_step.2 "$(step push "Run work-push" script work-push)"
answer current_step '{"answer":{"done":true,"output":"merged"}}'
"$PIPELINE" run 7 >/dev/null 2>&1
assert_equals '"pushed"' "$(report 2 '.output')" "runs the next script step after one reports"
teardown

setup
step_script work-check 'echo checked'
answer current_step "$(step deploy "Run work-deploy" script work-deploy)"
output=$("$PIPELINE" run 7 2>&1)
assert_equals "symphony has no script named work-deploy
GET current_step" "$output
$(calls)" "refuses a step naming a script this package does not contain, and runs nothing"
teardown

setup
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
"$PIPELINE" run 7 > "$WORK/out" 2>&1
stopped=$?
assert_equals "10
Agent step: Hand to builder on claude-sonnet-5-5
Agent: builder
Model: claude-sonnet-5-5
Title: Export quotes
Request: Reps want quotes as CSV
Acceptance criteria: A rep downloads a CSV" "$stopped
$(cat "$WORK/out")" "stops at an agent step and prints the agent, its model and the work"
teardown

setup
work_branch 7-export-quotes
pull_request '{"state":"MERGED","url":"https://github.com/acme/quotes/pull/5"}'
answer current_step.1 "$(step merge "Wait for the owner" owner)"
answer current_step '{"answer":{"done":true,"output":"merged"}}'
"$PIPELINE" run 7 >/dev/null 2>&1
assert_equals '{"step":"merge","result":"passed","output":"merged"}' "$(report 1 '{step, result, output}')" "reports a merged pull request at the owner's step"
teardown

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
