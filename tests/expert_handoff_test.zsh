#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
HANDOFF="$SCRIPT_DIR/../bin/expert-handoff.sh"

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

new_state() {
  STATE="$(mktemp -d "${TMPDIR:-/tmp}/expert_handoff_test.XXXXXX")"
  STATE="${STATE:A}"
  export SYMPHONY_EXPERTS_DIR="$STATE/experts"
  mkdir -p "$SYMPHONY_EXPERTS_DIR"
  REPO="$STATE/shop"
  mkdir -p "$REPO/app/views/quotes" "$REPO/app/models"
  git -C "$REPO" init -q
}

drop_state() {
  rm -rf "$STATE"
  unset SYMPHONY_EXPERTS_DIR
}

install_expert() {
  mkdir -p "$REPO/.claude/agents"
  printf -- '---\nname: %s-develop\n---\n' "$1" > "$REPO/.claude/agents/$1-develop.md"
}

patterns() {
  printf '%s' "$2" > "$SYMPHONY_EXPERTS_DIR/$1.json"
}

edit() {
  jq -nc --arg path "$1" --arg agent "${2:-}" \
    '{session_id: "s1", hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $path}}
     + (if $agent == "" then {} else {agent_id: "a1", agent_type: $agent} end)' \
    | "$HANDOFF" check
}

echo "expert-handoff.sh check:"

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
assert_contains '"permissionDecision":"deny"' "$(edit "$REPO/app/views/quotes/show.html.erb")" \
  "refuses the main session an edit to a file the installed expert owns"
drop_state

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
assert_equals "" "$(edit "$REPO/app/views/quotes/show.html.erb" widget_ui-develop)" \
  "lets the expert's own develop agent edit the file"
drop_state

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["config/initializers/widget_ui.rb"]}'
assert_equals "" "$(edit "$REPO/config/initializers/widget_ui.rb" widget_ui-install)" \
  "lets the expert's own install agent edit the file"
drop_state

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
assert_contains '"permissionDecision":"deny"' "$(edit "$REPO/app/views/quotes/show.html.erb" general-purpose)" \
  "refuses a subagent of any other type an edit to a file the installed expert owns"
drop_state

new_state
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
assert_equals "" "$(edit "$REPO/app/views/quotes/show.html.erb")" \
  "lets the main session edit the file when the gem's expert is not installed"
drop_state

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
assert_equals "" "$(edit "$REPO/app/models/quote.rb")" \
  "lets the main session edit a file no expert's patterns match"
drop_state

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
assert_contains '"permissionDecision":"deny"' "$(edit "$REPO/app/views/index.html.erb")" \
  "matches a double star pattern against a file with no folder in between"
drop_state

new_state
install_expert widget_ui
patterns default '{"widget_ui": ["app/views/**/*.erb"]}'
patterns shop '{"widget_ui": ["app/components/**/*.rb"]}'
mkdir -p "$REPO/app/components"
assert_contains '"permissionDecision":"deny"' "$(edit "$REPO/app/components/card.rb")" \
  "adds the patterns in the repo's own file to the shared ones"
drop_state

new_state
install_expert widget_ui
patterns shop '{"widget_ui": ["app/views/**/*.erb"]}'
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm start
git -C "$REPO" worktree add -q -b feature/quotes "$STATE/shop-feature-quotes"
mkdir -p "$STATE/shop-feature-quotes/app/views/quotes"
assert_contains '"permissionDecision":"deny"' "$(edit "$STATE/shop-feature-quotes/app/views/quotes/show.html.erb")" \
  "reads the main clone's patterns file from a linked worktree"
drop_state

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
