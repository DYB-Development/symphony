#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: expert-handoff.sh check  < hook.json
       expert-handoff.sh notice < hook.json

Keeps a session from writing code that an installed expert agent owns. `check`
refuses a file edit or write whose path matches a gem's patterns, when that
gem's expert is installed in the repo. `notice` prints, when a session starts,
one line for each gem with patterns that the repo's Gemfile or package.json
uses and whose expert is not installed.
Patterns are read from ~/.config/symphony/experts/default.json, and a repo adds
its own in ~/.config/symphony/experts/<repo>.json.
See ~/.claude/rules/expert-handoff.md.
USAGE
  exit 64
}

experts_dir="${SYMPHONY_EXPERTS_DIR:-$HOME/.config/symphony/experts}"

patterns_in() {
  [ -r "$1" ] && jq -c '.' "$1" 2>/dev/null || echo '{}'
}

main_clone() {
  dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
}

is_installed() {
  [ -f "$1/.claude/agents/$2-develop.md" ] || [ -f "$(main_clone "$1")/.claude/agents/$2-develop.md" ]
}

patterns_for() {
  local repo
  repo=$(basename "$(main_clone "$1")")
  jq -cn --argjson shared "$(patterns_in "$experts_dir/default.json")" \
    --argjson own "$(patterns_in "$experts_dir/$repo.json")" '
    reduce ($own | to_entries[]) as $entry ($shared; .[$entry.key] += $entry.value)'
}

owning_gem() {
  jq -rn --arg path "$2" --argjson patterns "$(patterns_for "$1")" '
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
  relative="$(cd "$dir" && pwd -P)${path#"$dir"}"
  relative="${relative#"$root"/}"
  while IFS= read -r gem; do
    [ -n "$gem" ] || continue
    is_installed "$root" "$gem" || continue
    case "$agent" in "$gem-develop"|"$gem-install") return 0 ;; esac
    refuse "$relative" "$gem"
    return 0
  done < <(owning_gem "$root" "$relative")
}

uses_gem() {
  { [ -f "$1/Gemfile" ] && grep -Eq "^[[:space:]]*gem[[:space:]]+[\"']$2[\"']" "$1/Gemfile"; } ||
    { [ -f "$1/package.json" ] && jq -e --arg gem "$2" \
      '(.dependencies // {}) + (.devDependencies // {}) | has($gem)' "$1/package.json" >/dev/null 2>&1; }
}

notice() {
  local root gem
  root=$(jq -r '.cwd // ""')
  root=$(git -C "${root:-.}" rev-parse --show-toplevel 2>/dev/null) || return 0
  while IFS= read -r gem; do
    uses_gem "$root" "$gem" || continue
    is_installed "$root" "$gem" && continue
    printf 'This repo uses %s, and its expert agent is not installed, so install it with the_local.\n' "$gem"
  done < <(patterns_for "$root" | jq -r 'keys[]')
}

case "${1:-}" in
  check) check ;;
  notice) notice ;;
  *) usage ;;
esac
