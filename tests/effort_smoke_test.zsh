#!/usr/bin/env zsh
# Smoke test for the Effort section: usage.sh --rows piped into
# effort.sh --render, over one throwaway transcript in a throwaway repo.
#
# Usage: zsh tests/effort_smoke_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
USAGE="$SCRIPT_DIR/../bin/usage.sh"
EFFORT="$SCRIPT_DIR/../bin/effort.sh"

REPO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/effort_smoke.XXXXXX")" && pwd -P)"
git -C "$REPO" init -q
git -C "$REPO" symbolic-ref HEAD refs/heads/main
export CLAUDE_CONFIG_DIR="$REPO/config"
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/a-repo/session.jsonl"
mkdir -p "${TRANSCRIPT:h}"

jq -nc --arg cwd "$REPO" '
  {type: "user", uuid: "p1", sessionId: "s1", isSidechain: false, cwd: $cwd,
   timestamp: "2026-01-03T00:00:00Z", message: {role: "user", content: "build the header"}},
  {type: "system", subtype: "turn_duration", uuid: "t1", sessionId: "s1", cwd: $cwd,
   timestamp: "2026-01-03T00:03:00Z", durationMs: 180000},
  {type: "user", uuid: "p2", sessionId: "s1", isSidechain: false, cwd: $cwd,
   timestamp: "2026-01-03T00:05:00Z", message: {role: "user", content: "make it blue"}}
' > "$TRANSCRIPT"

cd "$REPO"
expected="## Effort

- Sessions: 1
- Prompts: 2
- Words typed: 6
- Pasted blocks: 0
- Words pasted: 0
- Questions answered: 0
- Interruptions: 0
- Rejected tool calls: 0
- Claude working time: 3m
- Your active time: 2m"
actual="$("$USAGE" --rows | "$EFFORT" --render)"
cd "$SCRIPT_DIR"
rm -rf "$REPO"

echo "effort smoke:"
if [[ "$expected" == "$actual" ]]; then
  printf '  \033[32m✓\033[0m %s\n' "renders the Effort section from a transcript"
else
  printf '  \033[31m✗\033[0m %s\n' "renders the Effort section from a transcript"
  printf '      expected: %s\n      actual:   %s\n' "${(qqq)expected}" "${(qqq)actual}"
  exit 1
fi
