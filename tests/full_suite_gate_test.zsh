#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/full-suite-gate.sh"

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

from_agent() {
  jq -nc --arg command "$1" \
    '{hook_event_name: "PreToolUse", session_id: "s1", agent_id: "a1", agent_type: "general-purpose", tool_name: "Bash", tool_input: {command: $command, description: "Run tests"}}' \
    | "$GATE" check | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

from_main_session() {
  jq -nc --arg command "$1" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", tool_input: {command: $command, description: "Run tests"}}' \
    | "$GATE" check | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

echo "full-suite-gate.sh:"

assert_equals "" "$(from_main_session 'bin/rails test')" \
  "lets the main session run the whole suite"

assert_equals "deny" "$(from_agent 'bin/rails test')" \
  "refuses a subagent's run of the whole Rails suite"

assert_equals "deny" "$(from_agent 'cd ~/projects/shop-feature && PARALLEL_WORKERS=2 bin/rails test 2>&1 | tail -15')" \
  "refuses the whole suite after a cd, a setting and with its output piped"

let_through=()
for command in 'bin/rails test:all' 'bin/rails test:system' 'bin/ci' 'bundle exec rails test' 'bin/rails test --fail-fast'; do
  [[ "$(from_agent "$command")" == deny ]] || let_through+=("$command")
done
assert_equals "" "${(j:, :)let_through}" \
  "refuses every other way of running the whole Rails suite"

let_through=()
for command in 'bundle exec rake' 'bundle exec rake test' 'rake test' 'bundle exec rspec' 'bun test' 'bun run test' 'bun run test:e2e' 'npm test' 'yarn test' './run_tests.sh' 'run_tests.sh --seed 4'; do
  [[ "$(from_agent "$command")" == deny ]] || let_through+=("$command")
done
assert_equals "" "${(j:, :)let_through}" \
  "refuses the whole suite of a gem, a Bun or Node app and this repo"

allowed=()
for command in 'bundle exec rake test TEST=test/quote_test.rb' 'bundle exec rspec spec/models/quote_spec.rb' 'bun test apps/api/quote.test.ts' './run_tests.sh tests/keep_working_test.zsh'; do
  [[ -z "$(from_agent "$command")" ]] || allowed+=("$command")
done
assert_equals "" "${(j:, :)allowed}" \
  "lets a subagent run one file with any of those runners"

assert_equals "" "$(from_agent 'cd ~/projects/shop-feature && bin/rails test test/models/quote_test.rb 2>&1 | tail -5')" \
  "lets a subagent run one test file"

assert_equals "" "$(from_agent 'bin/rails test test/models/quote_test.rb:42')" \
  "lets a subagent run one test by its line"

assert_equals "" "$(from_agent 'bin/rails test -n test_converts_a_quote')" \
  "lets a subagent run one test by its name"

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
