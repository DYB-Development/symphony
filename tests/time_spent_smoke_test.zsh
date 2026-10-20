#!/usr/bin/env zsh
# Smoke test for the Time Spent section: usage.sh --spans piped into
# time-spent.sh --render, over one throwaway transcript in a throwaway repo.
#
# Usage: zsh tests/time_spent_smoke_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
USAGE="$SCRIPT_DIR/../bin/usage.sh"
TIME_SPENT="$SCRIPT_DIR/../bin/time-spent.sh"

REPO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/time_spent_smoke.XXXXXX")" && pwd -P)"
git -C "$REPO" init -q
git -C "$REPO" symbolic-ref HEAD refs/heads/main
export CLAUDE_CONFIG_DIR="$REPO/config"
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/a-repo/session.jsonl"
mkdir -p "${TRANSCRIPT:h}"

jq -nc --arg cwd "$REPO" '
  {type: "user", uuid: "p1", sessionId: "s1", isSidechain: false, cwd: $cwd,
   timestamp: "2026-01-03T00:00:00Z", message: {role: "user", content: "run the tests"}},
  {type: "assistant", sessionId: "s1", cwd: $cwd, timestamp: "2026-01-03T00:00:10Z",
   message: {id: "m1", content: [{type: "tool_use", id: "toolu_1", name: "Bash", input: {command: "bin/rails test"}}]}},
  {type: "user", uuid: "r1", sessionId: "s1", isSidechain: false, cwd: $cwd, timestamp: "2026-01-03T00:01:10Z",
   message: {role: "user", content: [{type: "tool_result", tool_use_id: "toolu_1", content: "ok"}]}, toolUseResult: {}},
  {type: "system", subtype: "turn_duration", uuid: "t1", sessionId: "s1", cwd: $cwd,
   timestamp: "2026-01-03T00:03:00Z", durationMs: 180000},
  {type: "user", uuid: "p2", sessionId: "s1", isSidechain: false, cwd: $cwd,
   timestamp: "2026-01-03T00:05:00Z", message: {role: "user", content: "thanks"}}
' > "$TRANSCRIPT"

cd "$REPO"
expected="## Time Spent

- Total: 5m
- Waiting on the owner: 2m
- Model time: 2m
- Tool calls: 1m"
actual="$("$USAGE" --spans | "$TIME_SPENT" --render)"
cd "$SCRIPT_DIR"
rm -rf "$REPO"

echo "time spent smoke:"
if [[ "$expected" == "$actual" ]]; then
  printf '  \033[32m✓\033[0m %s\n' "renders the Time Spent section from a transcript"
else
  printf '  \033[31m✗\033[0m %s\n' "renders the Time Spent section from a transcript"
  printf '      expected: %s\n      actual:   %s\n' "${(qqq)expected}" "${(qqq)actual}"
  exit 1
fi
