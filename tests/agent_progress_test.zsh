#!/usr/bin/env zsh
# Tests for bin/scribe-step.sh and bin/agent-progress.sh. Every case writes its
# logs into a throwaway directory, so no real progress log is touched.
#
# Usage: zsh tests/agent_progress_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STEP="$SCRIPT_DIR/../bin/scribe-step.sh"

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

echo "scribe-step.sh:"

assert_equals "acme/quotes#42 · 3. Run every check" \
  "$("$STEP" "acme/quotes#42" "3. Run every check" 2>&1)" \
  "prints the target and the step it is given"

assert_equals "acme/quotes#42 · 3. Run every check · 4/9 Dependencies" \
  "$("$STEP" "acme/quotes#42" "3. Run every check" "4/9 Dependencies" 2>&1)" \
  "prints a position inside the step after the step"

PROGRESS="$SCRIPT_DIR/../bin/agent-progress.sh"

new_dir() { LOGS="$(mktemp -d "${TMPDIR:-/tmp}/agent_progress_test.XXXXXX")"; }
drop_dir() { rm -rf "$LOGS"; }

bash_payload() {
  jq -nc --arg id "$1" --arg type "$2" --arg command "$3" \
    '{hook_event_name: "PreToolUse", session_id: "s1", agent_id: $id, agent_type: $type, tool_name: "Bash", tool_input: {command: $command}}'
}

record() {
  AGENT_PROGRESS_DIR="$LOGS" AGENT_PROGRESS_NOW="$1" "$PROGRESS" record
}

ran_payload() {
  jq -nc --arg id "$1" --arg type "$2" --arg command "$3" --arg stdout "$4" \
    '{hook_event_name: "PostToolUse", session_id: "s1", agent_id: $id, agent_type: $type, tool_name: "Bash", tool_input: {command: $command}, tool_response: {stdout: $stdout, stderr: "", interrupted: false, exit_code: 0}}'
}

echo "agent-progress.sh record:"

new_dir
ran_payload a1 review-scribe 'S="acme/quotes#42"; ~/.claude/bin/scribe-step.sh "$S" "$T"' \
  $'acme/quotes#42 · 3. Run every check\n' | record 1000
assert_equals $'1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records the target and step a mark printed when its command passed them in shell variables"
drop_dir

new_dir
ran_payload a1 review-scribe '~/.claude/bin/scribe-step.sh "$S" "2. Read the ticket" && ~/.claude/bin/scribe-step.sh "$S" "3. Run every check" "1/9 Security"' \
  $'acme/quotes#42 · 2. Read the ticket\nacme/quotes#42 · 3. Run every check · 1/9 Security\n' | record 1000
assert_equals $'1000\treview-scribe\tacme/quotes#42\t2. Read the ticket\ts1\n1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\t1/9 Security' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records each mark one command printed as its own step"
drop_dir

new_dir
bash_payload a1 review-scribe '~/.claude/bin/scribe-step.sh "$S" "3. Run every check"' | record 1000
assert_equals "" "$(ls -A "$LOGS")" "records no mark before its command has run"
drop_dir

new_dir
jq -nc '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", tool_input: {command: "~/.claude/bin/scribe-step.sh \"acme/quotes#42\" \"1. Read the diff\""}}' | record 1000
assert_equals "" "$(ls -A "$LOGS")" "records nothing for a command run outside a subagent"
drop_dir

new_dir
bash_payload a1 review-scribe '~/.claude/bin/judge-claims.sh /repo/.review-42.claims.json' | record 1000
assert_equals $'1000\treview-scribe\t\truns judge-claims\ts1' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records a symphony script a subagent runs"
drop_dir

new_dir
jq -nc '{hook_event_name: "SubagentStop", session_id: "s1", agent_id: "a1", agent_type: "review-scribe"}' | record 1000
assert_equals $'1000\treview-scribe\t\tfinished\ts1' \
  "$(cat "$LOGS/a1.log" 2>&1)" \
  "records that a subagent finished"
drop_dir

status() {
  AGENT_PROGRESS_DIR="$LOGS" AGENT_PROGRESS_NOW="$1" "$PROGRESS" 2>&1
}

echo "agent-progress.sh:"

new_dir
printf '1000\treview-scribe\tacme/quotes#42\t9. Point each claim\n1052\treview-scribe\t\truns judge-claims\n' > "$LOGS/a1.log"
assert_equals "review-scribe acme/quotes#42 — runs judge-claims — 4m08s on this step, 5m00s in all" \
  "$(status 1300)" \
  "shows a running agent's target, latest step and how long it has taken"
drop_dir

new_dir
printf '1000\treview-scribe\tacme/quotes#42\t1. Read the diff\n1200\treview-scribe\t\tfinished\n' > "$LOGS/a1.log"
assert_equals "No agents running." "$(status 1300)" "leaves out an agent that has finished"
drop_dir

# An agents directory holding a review-scribe whose instructions number 11 steps.
new_agents() {
  AGENTS="$LOGS/agents"
  mkdir -p "$AGENTS"
  for n in {1..11}; do printf '%d. **Step %d.** Do it.\n' $n $n; done > "$AGENTS/review-scribe.md"
}

lines() {
  AGENT_PROGRESS_DIR="$LOGS" AGENT_PROGRESS_AGENTS="$AGENTS" AGENT_PROGRESS_NOW=1300 "$PROGRESS" line "$1" 2>&1
}

echo "agent-progress.sh line:"

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\n' > "$LOGS/a1.log"
assert_equals $'review-scribe acme/quotes#42\n█░░░░░░░░░ 3/11 · Run every check' "$(lines s1)" \
  "shows a running scribe's type and target above a bar of its step out of its numbered steps"
drop_dir

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\t9/9 Missed changes\n' > "$LOGS/a1.log"
assert_equals $'review-scribe acme/quotes#42\n██░░░░░░░░ 3/11 · Run every check · 9/9 Missed changes' "$(lines s1)" \
  "fills the bar through a step by the position marked inside it, and shows the position"
drop_dir

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\tcriterion 1 of 2 Export button\n' > "$LOGS/a1.log"
assert_equals $'review-scribe acme/quotes#42\n██░░░░░░░░ 3/11 · Run every check · criterion 1 of 2 Export button' "$(lines s1)" \
  "fills the bar through a step by a position written as k of K, and shows the position"
drop_dir

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t9. Point each claim\ts1\n1052\treview-scribe\t\truns judge-claims\ts1\n' > "$LOGS/a1.log"
assert_equals $'review-scribe acme/quotes#42\n███████░░░ 9/11 · Point each claim' "$(lines s1)" \
  "keeps the bar and the step when the scribe runs a script without marking a step"
drop_dir

new_dir
new_agents
printf '1000\tExplore\t\truns plan-progress\ts1\n' > "$LOGS/a1.log"
assert_equals "Explore · runs plan-progress" "$(lines s1)" \
  "shows an agent with no numbered steps by its type, target and last step, with no bar"
drop_dir

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts2\n' > "$LOGS/a1.log"
assert_equals "" "$(lines s1)" "never shows a subagent running in another session"
drop_dir

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\n1200\treview-scribe\t\tfinished\ts1\n' > "$LOGS/a1.log"
assert_equals "" "$(lines s1)" "shows nothing for a subagent that has stopped"
drop_dir

zmodload zsh/datetime
# Sets a file's modification time to $2 seconds ago.
age() { touch -t "$(strftime %Y%m%d%H%M.%S $(( EPOCHSECONDS - $2 )))" "$1"; }

new_dir
new_agents
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\n' > "$LOGS/a1.log"
age "$LOGS/a1.log" 3700
assert_equals "" "$(lines s1)" "stops showing an agent that has recorded nothing for an hour"
drop_dir

new_dir
printf '1000\treview-scribe\t\tfinished\ts1\n' > "$LOGS/old.log"
age "$LOGS/old.log" 90000
jq -nc '{hook_event_name: "SubagentStop", session_id: "s1", agent_id: "a2", agent_type: "pr-scribe"}' | record 1000
assert_equals "a2.log" "$(ls "$LOGS")" "removes a finished agent's log a day after it finished"
drop_dir

new_dir
new_agents
for n in {1..10000}; do print -r -- $'1000\treview-scribe\t\tfinished\ts0' > "$LOGS/old$n.log"; done
print -rl -- "$LOGS"/old*.log | xargs touch -t "$(strftime %Y%m%d%H%M.%S $(( EPOCHSECONDS - 7200 )))"
printf '1000\treview-scribe\tacme/quotes#42\t3. Run every check\ts1\n' > "$LOGS/a1.log"
started=$EPOCHREALTIME
lines s1 >/dev/null
elapsed=$(( EPOCHREALTIME - started ))
assert_equals "1" "$(( elapsed < 1 ))" "shows agent steps in under a second with ten thousand earlier logs"
drop_dir

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
