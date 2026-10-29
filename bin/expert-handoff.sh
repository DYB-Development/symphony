#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: expert-handoff.sh check < hook.json

Keeps a session from writing code that an installed expert agent owns. `check`
refuses a file edit or write whose path matches a gem's patterns, when that
gem's expert is installed in the repo.
Patterns are read from ~/.config/symphony/experts/default.json.
See ~/.claude/rules/expert-handoff.md.
USAGE
  exit 64
}

experts_dir="${SYMPHONY_EXPERTS_DIR:-$HOME/.config/symphony/experts}"

patterns_for_all() {
  local file="$experts_dir/default.json"
  [ -r "$file" ] && jq -c '.' "$file" 2>/dev/null || echo '{}'
}

owning_gem() {
  jq -rn --arg path "$1" --argjson patterns "$(patterns_for_all)" '
    def regex: gsub("\\."; "\\.") | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002")
      | gsub("\\*"; "[^/]*") | gsub("\\?"; "[^/]") | gsub("\u0001"; "(.*/)?") | gsub("\u0002"; ".*")
      | "^" + . + "$";
    [$patterns | to_entries[] | select(any(.value[]; . as $glob | $path | test($glob | regex))) | .key]
    | .[]'
}

refuse() {
  jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $text}}' \
    --arg text "$1 belongs to the $2 expert, which is installed in this repo. Hand this work to it with the Agent tool, subagent_type \"$2-develop\", rather than writing it here."
}

check() {
  local payload path agent dir root relative gem
  payload=$(cat)
  path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
  agent=$(printf '%s' "$payload" | jq -r '.agent_type // ""')
  [ -n "$path" ] || return 0
  dir=$(dirname "$path")
  while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
  relative="${path#"$root"/}"
  while IFS= read -r gem; do
    [ -n "$gem" ] || continue
    [ -f "$root/.claude/agents/$gem-develop.md" ] || continue
    case "$agent" in "$gem-develop"|"$gem-install") return 0 ;; esac
    refuse "$relative" "$gem"
    return 0
  done < <(owning_gem "$relative")
}

case "${1:-}" in
  check) check ;;
  *) usage ;;
esac
