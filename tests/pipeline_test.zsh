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

STUBS="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pipeline_test_stubs.XXXXXX")" && pwd -P)"
cat > "$STUBS/stub" <<'STUB'
#!/usr/bin/env bash
work="$PIPELINE_TEST_WORK"
case "${0##*/}" in
  curl)
    [ -z "${STUB_CURL_DOWN:-}" ] || exit 7
    url="" data="" method=GET
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method="$2"; shift ;;
        -d|--data) data="$2"; method=POST; shift ;;
        http*) url="$1" ;;
      esac
      shift
    done
    name="${url##*/}"; name="${name%%\?*}"
    printf '%s %s %s\n' "$method" "$name" "$data" >> "$work/calls"
    count=$(( $(cat "$work/count.$name" 2>/dev/null || echo 0) + 1 ))
    echo "$count" > "$work/count.$name"
    answer="$work/answers/$name.$count"
    [ -f "$answer" ] || answer="$work/answers/$name"
    printf '%s\n%s' "$(cat "$answer" 2>/dev/null || echo '{"answer":null}')" "$(cat "$work/answers/$name.code" 2>/dev/null || echo 200)"
    ;;
  gh)
    printf '%s\n' "$*" >> "$work/gh_calls"
    cat "$work/gh_output"
    ;;
  usage.sh)
    printf '%s\n' "$*" >> "$work/usage_calls"
    cat "$work/usage_output"
    ;;
  pr-wait.sh)
    printf '%s\n' "$*" >> "$work/wait_calls"
    cat "$work/wait_output"
    exit "$(cat "$work/wait_code")"
    ;;
  *.sh)
    . "$work/steps/${0##*/}.body"
    ;;
esac
STUB
chmod +x "$STUBS/stub"
PIPELINE_TEST_WORK=/nonexistent "$STUBS/stub" >/dev/null 2>&1

link_stub() {
  ln -s "$STUBS/stub" "$1"
}

setup() {
  WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pipeline_test.XXXXXX")" && pwd -P)"
  export PIPELINE_TEST_WORK="$WORK"
  mkdir -p "$WORK/bin" "$WORK/answers" "$WORK/settings" "$WORK/repo"
  printf 'url=https://dyb.example\ntoken=secret\n' > "$WORK/settings/dyb_web"
  export SYMPHONY_CONFIG_DIR="$WORK/settings" SYMPHONY_SESSION="session-a"
  link_stub "$WORK/bin/curl"
  path=("$WORK/bin" $path)
  git -C "$WORK/repo" init -q --template=
  cd "$WORK/repo"
}

teardown() {
  cd "$SCRIPT_DIR"
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
  unset PIPELINE_TEST_WORK SYMPHONY_CONFIG_DIR SYMPHONY_SESSION STUB_CURL_DOWN SYMPHONY_STEP_DIR SYMPHONY_USAGE SYMPHONY_AGENT_DIR SYMPHONY_PR_WAIT
}

step_script() {
  mkdir -p "$WORK/steps"
  printf '%s\n' "$2" > "$WORK/steps/$1.sh.body"
  [[ -L "$WORK/steps/$1.sh" ]] || link_stub "$WORK/steps/$1.sh"
  export SYMPHONY_STEP_DIR="$WORK/steps"
}

report() { grep '^POST report_step ' "$WORK/calls" | sed -n "${1:-1}p" | cut -d' ' -f3- | jq -c "$2"; }

calls() { cut -d' ' -f1,2 "$WORK/calls" | tr '\n' ',' | sed 's/,$//'; }

work_branch() {
  git -C "$WORK/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m start
  git -C "$WORK/repo" branch "$1"
}

pull_request() {
  printf '%s' "$1" > "$WORK/gh_output"
  [[ -L "$WORK/bin/gh" ]] || link_stub "$WORK/bin/gh"
}

agent_report() {
  printf '%s\n' "$@" > "$WORK/report.md"
}

measured() {
  printf '%s' "$1" > "$WORK/usage_output"
  [[ -L "$WORK/bin/usage.sh" ]] || link_stub "$WORK/bin/usage.sh"
  export SYMPHONY_USAGE="$WORK/bin/usage.sh"
}

waiting() {
  printf '%s' "$1" > "$WORK/wait_output"
  printf '%s' "$2" > "$WORK/wait_code"
  [[ -L "$WORK/bin/pr-wait.sh" ]] || link_stub "$WORK/bin/pr-wait.sh"
  export SYMPHONY_PR_WAIT="$WORK/bin/pr-wait.sh"
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

setup
work_branch 7-export-quotes
pull_request '{"state":"CLOSED","url":"https://github.com/acme/quotes/pull/5"}'
answer current_step.1 "$(step merge "Wait for the owner" owner)"
answer current_step '{"answer":{"done":true,"output":"stopped"}}'
"$PIPELINE" run 7 >/dev/null 2>&1
assert_equals '{"result":"failed","output":"closed"}' "$(report 1 '{result, output}')" "reports a closed pull request at the owner's step"
teardown

setup
work_branch 7-export-quotes
pull_request '{"state":"OPEN","url":"https://github.com/acme/quotes/pull/5"}'
answer current_step "$(step merge "Wait for the owner" owner)"
"$PIPELINE" run 7 > "$WORK/out" 2>&1
stopped=$?
assert_equals "11
Export quotes waits on the owner: https://github.com/acme/quotes/pull/5" "$stopped
$(cat "$WORK/out")" "stops and flags an open pull request as waiting on the owner"
teardown

setup
work_branch 7-export-quotes
measured ""
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
agent_report "Built the export." "Result: passed"
"$PIPELINE" report 7 "$WORK/report.md" >/dev/null 2>&1
assert_equals '{"step":"build","result":"passed"}' "$(report 1 '{step, result}')" "posts the result named on an agent report's last line"
teardown

setup
work_branch 7-export-quotes
measured "claude-sonnet-5-5	120000"
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
agent_report "Built the export." "Result: passed"
"$PIPELINE" report 7 "$WORK/report.md" >/dev/null 2>&1
assert_equals '{"model":"claude-sonnet-5-5","tokens":120000}
--agent-run builder' "$(report 1 '{model, tokens}')
$(cat "$WORK/usage_calls")" "posts the model and tokens the transcripts recorded for the agent's latest run"
teardown

setup
work_branch 7-export-quotes
measured ""
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
agent_report "Built the export." "Result: passed"
"$PIPELINE" report 7 "$WORK/report.md" >/dev/null 2>&1
assert_equals '{"tokens":null,"output":"Built the export.\nResult: passed\nTokens: not measured"}' "$(report 1 '{tokens, output}')" "marks the tokens as not measured when the transcripts hold no run of the agent"
teardown

setup
work_branch 7-export-quotes
measured ""
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
agent_report "Built the export." "All done."
output=$("$PIPELINE" report 7 "$WORK/report.md" 2>&1)
assert_equals "The report's last line names no result
GET current_step" "$output
$(calls)" "refuses a report whose last line names no result, and posts nothing"
teardown

setup
work_branch 7-export-quotes
measured ""
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
agent_report "Built the export." "Result: built"
"$PIPELINE" report 7 "$WORK/report.md" >/dev/null 2>&1
built=$(report 1 '.result')
agent_report "Could not build it." "Result: stuck"
"$PIPELINE" report 7 "$WORK/report.md" >/dev/null 2>&1
assert_equals '"passed" "failed"' "$built $(report 2 '.result')" "posts a builder's built as passed and stuck as failed"
teardown

setup
work_branch 7-export-quotes
step_script work-check 'echo "$WORK_ITEM_ID $(jq -r .kind <<<"$PIPELINE_STEP")"'
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
assert_equals "7 agent" "$("$PIPELINE" check 7 2>&1)" "runs the check step for the step a work item is on"
teardown

setup
work_branch 7-export-quotes
measured "claude-opus-5-5	90000"
pull_request '{"state":"OPEN","url":"https://github.com/acme/quotes/pull/5"}'
answer current_step "$(step open-pr "Hand to pr-scribe on claude-opus-5-5" agent)"
"$PIPELINE" report-pr 7 >/dev/null 2>&1
assert_equals '{"result":"passed","output":"https://github.com/acme/quotes/pull/5","model":"claude-opus-5-5","tokens":90000}' "$(report 1 '{result, output, model, tokens}')" "reports the pull request step as opened when the branch has an open pull request"
teardown

setup
work_branch 7-export-quotes
measured ""
pull_request '{"state":"CLOSED","url":"https://github.com/acme/quotes/pull/5"}'
answer current_step "$(step open-pr "Hand to pr-scribe on claude-opus-5-5" agent)"
"$PIPELINE" report-pr 7 >/dev/null 2>&1
assert_equals '"failed"' "$(report 1 '.result')" "reports the pull request step as failed when the branch has no open pull request"
teardown

setup
mkdir -p "$WORK/agents"
export SYMPHONY_AGENT_DIR="$WORK/agents"
answer current_step "$(step build "Hand to builder on claude-sonnet-5-5" agent)"
"$PIPELINE" run 7 > "$WORK/out" 2>&1
stopped=$?
assert_equals "66
symphony defines no agent named builder" "$stopped
$(cat "$WORK/out")" "refuses an agent step naming an agent symphony does not define"
teardown

setup
answer current_step "$(step watch "Run work-watch" script work-watch)"
"$PIPELINE" run 7 > "$WORK/out" 2>&1
stopped=$?
assert_equals "12
Watch the pull request: ~/.claude/bin/pipeline.sh watch 7" "$stopped
$(cat "$WORK/out")" "stops at the watch step and prints the command to start in the background"
teardown

setup
work_branch 7-export-quotes
pull_request '{"number":5,"state":"OPEN","url":"https://github.com/acme/quotes/pull/5"}'
waiting $'CI passed on PR #5, opened it\nPR #5 was merged\n' 0
answer current_step "$(step watch "Run work-watch" script work-watch)"
output=$("$PIPELINE" watch 7 2>&1)
assert_equals '{"step":"watch","result":"passed","output":"CI passed on PR #5, opened it"}
acme/quotes 5
PR #5 was merged' "$(report 1 '{step, result, output}')
$(cat "$WORK/wait_calls")
$(printf '%s\n' "$output" | tail -1)" "reports the checks as passed, then says whether the pull request was merged or closed"
teardown

setup
work_branch 7-export-quotes
pull_request '{"number":5,"state":"OPEN","url":"https://github.com/acme/quotes/pull/5"}'
waiting $'CI failed on PR #5: tests\n' 1
answer current_step "$(step watch "Run work-watch" script work-watch)"
"$PIPELINE" watch 7 >/dev/null 2>&1
stopped=$?
assert_equals '1 {"result":"failed","output":"CI failed on PR #5: tests"}' "$stopped $(report 1 '{result, output}')" "reports the checks as failed, naming the check that failed, and exits"
teardown

setup
work_branch 7-export-quotes
pull_request '{"number":5,"state":"OPEN","url":"https://github.com/acme/quotes/pull/5"}'
waiting $'PR #5 was merged\n' 0
answer current_step "$(step watch "Run work-watch" script work-watch)"
"$PIPELINE" watch 7 >/dev/null 2>&1
assert_equals '{"result":"passed","output":"PR #5 was merged"}' "$(report 1 '{result, output}')" "reports the watch step as passed when the pull request is merged before any check reports"
teardown

rm -rf "$STUBS"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
