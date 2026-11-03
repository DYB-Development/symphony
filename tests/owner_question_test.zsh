#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
GATE="$SCRIPT_DIR/../bin/owner-question.sh"

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

STATE="$(mktemp -d "${TMPDIR:-/tmp}/owner_question_test.XXXXXX")"
trap 'rm -rf "$STATE"' EXIT
export OWNER_QUESTION_DIR="$STATE/marks"

reset_marks() { rm -rf "$OWNER_QUESTION_DIR"; }

prompt() {
  jq -nc --arg text "$1" '{hook_event_name: "UserPromptSubmit", session_id: "s1", prompt: $text}' | "$GATE" record
}

asked() {
  if "$GATE" asked s1; then echo yes; else echo no; fi
}

echo "owner-question.sh record:"

reset_marks; prompt "are you following the rules?"
assert_equals "yes" "$(asked)" "marks a prompt ending in a question mark as a question"

reset_marks; prompt "so again what is the plan"
assert_equals "yes" "$(asked)" "marks a prompt opening with a question word and no question mark as a question"

reset_marks; prompt "are you ok?"; prompt "go ahead with the plan"
assert_equals "no" "$(asked)" "removes the mark when the owner's next prompt is an instruction"

reset_marks; prompt "are you ok?"; prompt "<task-notification>
<task-id>b1</task-id>
<status>completed</status>
</task-notification>"
assert_equals "yes" "$(asked)" "keeps the mark when a background task notification arrives"

reset_marks; prompt "This keeps failing. How do we solve this."
assert_equals "yes" "$(asked)" "reads the last sentence of a prompt to tell whether it is a question"

reset_marks; prompt "Why is this broken?
<pasted_content id=\"a1\">
ran the suite.
</pasted_content id=\"a1\">"
assert_equals "yes" "$(asked)" "leaves pasted text out when reading the prompt"

reset_marks; prompt "stop"
assert_equals "yes" "$(asked)" "marks a prompt telling the session to stop"

tool_call() {
  jq -nc --arg tool "$1" --argjson input "${2:-{\}}" --arg agent "${3:-}" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $tool, tool_input: $input, agent_id: $agent}' | "$GATE" check
}

decision() {
  tool_call "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

echo "owner-question.sh check:"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(decision Edit '{"file_path":"/a"}')" "refuses a file edit after the owner asks a question"

reset_marks; prompt "are you ok?"
assert_equals "" "$(decision Read '{"file_path":"/a"}')" "lets a file be read while the question is being answered"

stop_turn() {
  jq -nc '{hook_event_name: "Stop", session_id: "s1"}' | "$GATE" stop
}

reset_marks; prompt "are you ok?"; stop_turn
assert_equals "deny" "$(decision Read '{"file_path":"/a"}')" "refuses a read once the turn that answered the question has ended"

reset_marks; prompt "are you ok?"
assert_equals "" "$(decision Edit '{"file_path":"/a"}' agent-1)" "lets a running subagent carry on"

bash_decision() {
  decision Bash "$(jq -nc --arg c "$1" '{command: $c}')"
}

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git -C /a status --short | head -3')" "lets a read-only shell command run while the question is being answered"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'git status && git commit -m done')" "refuses a shell command that changes something after a read-only one"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'cat a > b')" "refuses a shell command that writes a file through a redirect"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'gh pr view 199 2>&1')" "lets a read-only shell command send its errors to its output"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git status >/dev/null 2>/dev/null')" "lets a read-only shell command discard its output"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'cat a >/dev/nullx')" "refuses a redirect to a file whose name only starts with the discard path"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'timeout 60 gh pr view 199 -R a/b')" "lets a read-only shell command run under a time limit"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'timeout 60 rm a')" "refuses a changing shell command run under a time limit"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'F=/a; jq . $F')" "lets a variable be set before a read-only shell command"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'F=/a jq . $F')" "lets a variable be set for a read-only shell command"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'F=/a rm b')" "refuses a variable set for a changing shell command"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git show $(git rev-parse HEAD)')" "lets a read-only shell command use the output of another"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'echo $(rm a)')" "refuses a changing shell command run inside a read-only one"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'echo "$(rm a)"')" "refuses a changing shell command run inside quoted text"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'echo `rm a`')" "refuses a shell command run through backticks"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'for n in 1 2; do gh pr view $n; done')" "lets a loop of read-only shell commands run"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'if [ -f a ]; then cat a; fi')" "lets a condition around a read-only shell command run"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git diff --name-only | while read f; do cat $f; done')" "lets a read-only shell command read the lines of another in a loop"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'for n in 1; do rm $n; done')" "refuses a loop of changing shell commands"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git diff --name-only | xargs grep a')" "lets a read-only shell command run through xargs"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'ls | xargs -n 1 -I {} cat {}')" "lets a read-only shell command run through xargs with its options"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'ls | xargs rm')" "refuses a changing shell command run through xargs"

reset_marks; prompt "are you ok?"
assert_equals "deny" "$(bash_decision 'ls | xargs -n 1 rm')" "refuses a changing shell command run through xargs with its options"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git -C /a fetch -q origin && git rev-list --count HEAD')" "lets git fetch and read commits while the question is being answered"

reset_marks; prompt "are you ok?"
assert_equals "" "$(bash_decision 'git ls-tree -r HEAD; git cat-file -p HEAD; git for-each-ref')" "lets git read trees, objects and refs while the question is being answered"

reset_marks; prompt "are you ok?"
assert_equals "" "$(decision Agent '{"subagent_type":"Explore"}')" "lets a search agent be started while the question is being answered"

reset_marks; prompt "are you ok?"
touch -t 202001010000 "$OWNER_QUESTION_DIR"/*
assert_equals "" "$(decision Edit '{"file_path":"/a"}')" "ignores a mark more than a day old"

echo "the hooks in hooks.json:"

HOOKS="$SCRIPT_DIR/../hooks/hooks.json"
wired() { jq -r --arg event "$1" '.hooks[$event][].hooks[].command' "$HOOKS" | grep -cF "$2"; }

assert_equals "1 1 1 1" "$(wired UserPromptSubmit 'owner-question.sh record') $(wired PreToolUse 'owner-question.sh check') $(wired Stop 'owner-question.sh stop') $(wired Stop 'keep-working.sh check')" "runs the question block and the stop check from the hook file"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
