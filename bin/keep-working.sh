#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: keep-working.sh check < hook.json

Refuses a stop while the branch the session is working on has unfinished work.
See ~/.claude/rules/develop_process_rules.md.
USAGE
  exit 64
}

[ "${1:-}" = check ] || usage

index="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/session-worktrees.tsv"

is_linked_worktree() {
  [ "$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" != "$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]
}

session_worktree() {
  local root
  [ -f "$index" ] || return 0
  while IFS= read -r root; do
    if [ ! -d "$root" ] || is_linked_worktree "$root"; then
      printf '%s\n' "$root"
      return 0
    fi
  done < <(awk -F '\t' -v t="$1" '$2 == t { print $1 }' "$index" | sed -n '1!G;h;$p')
}

commits_ahead() {
  local worktree=$1 base
  shift
  for base in "$@"; do
    git -C "$worktree" rev-parse -q --verify "$base" >/dev/null 2>&1 || continue
    git -C "$worktree" rev-list --count "$base..HEAD"
    return 0
  done
  printf '0\n'
}

hook=$(cat)
mark="${KEEP_WORKING_DIR:-$HOME/.claude/keep-working}/$(jq -r '.session_id // empty' <<< "$hook" | shasum | cut -c1-40)"

github_failed() {
  echo "keep-working.sh: GitHub could not be read, so the session stopped unchecked" >&2
  exit 0
}

refuse() {
  local fingerprint=$1 reason=$2 message=$3 count=0
  if [ -f "$mark.refusals" ] && [ "$(sed -n 2p "$mark.refusals")" = "$fingerprint" ]; then
    count=$(sed -n 1p "$mark.refusals")
  fi
  if [ "$count" -ge 3 ]; then
    jq -nc --arg text "$message" '{systemMessage: $text}'
    exit 0
  fi
  mkdir -p "$(dirname "$mark")"
  printf '%s\n%s\n' "$((count + 1))" "$fingerprint" > "$mark.refusals"
  jq -nc --arg reason "$reason" '{decision: "block", reason: $reason}'
}

remember_issue() {
  mkdir -p "$(dirname "$mark")"
  printf '%s %s\n' "$(git -C "$1" remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')" "$2" > "$mark.issue"
}

next_in_plan() {
  local repo issue body open next
  [ -f "$mark.issue" ] || return 0
  read -r repo issue < "$mark.issue"
  body=$(gh issue view "$issue" --repo "$repo" --json body) || github_failed
  open=$(gh issue list --repo "$repo" --state open --limit 200 --json number,labels,body) || github_failed
  next=$(jq -r --argjson current "$issue" --slurpfile source <(printf '%s' "$body") '
    def plan: .body // "" | (capture("## Part of\\s*\\n(?<part>[^\\n]*), stage [0-9]+ of [0-9]+").part // empty);
    def priority: [.labels[].name] | if any(. == "priority:high") then 0 elif any(. == "priority:medium") then 1 else 2 end;
    def blockers: .body // "" | [scan("Blocked by ([A-Za-z0-9_./-]*)#([0-9]+)")];
    ($source[0] | plan) as $plan
    | (map(.number | tostring)) as $open_numbers
    | map(select(plan == $plan and .number != $current))
    | map(select(any(blockers[]; .[0] != "" or (.[1] | IN($open_numbers[]))) | not))
    | map(select(any(.labels[]; .name == "blocked") | not))
    | sort_by(priority, .number) | first | .number // empty
  ' <<< "$open")
  if [ -z "$next" ]; then
    rm -f "$mark.issue"
    return 0
  fi
  refuse "next $next" \
    "The pull request merged and issue #$next is next in this plan. Clean up the merged branch, then start issue #$next with the next-task process. Stop only if the owner says so." \
    "Stopped before starting issue #$next, the next in this plan."
}

[ "$(jq '.background_tasks // [] | map(select(.status == "running")) | length' <<< "$hook")" -eq 0 ] || exit 0
transcript=$(jq -r '.transcript_path // empty' <<< "$hook")
worktree=$(session_worktree "$transcript")
[ -n "$worktree" ] || exit 0
[ -d "$worktree" ] || { next_in_plan; exit 0; }

branch=$(git -C "$worktree" branch --show-current)
started=$(commits_ahead "$worktree" origin/HEAD origin/main)
pull_requests=$(cd "$worktree" && gh pr list --head "$branch" --state all --limit 1 --json number,state,closingIssuesReferences) || github_failed
state=$(jq -r '.[0].state // "NONE"' <<< "$pull_requests")
issue=$(jq -r '.[0].closingIssuesReferences[0].number // empty' <<< "$pull_requests")
[ -z "$issue" ] || remember_issue "$worktree" "$issue"

case "$state" in
  CLOSED) exit 0 ;;
  MERGED) next_in_plan; exit 0 ;;
esac

unfinished=()
[ -z "$(git -C "$worktree" status --porcelain)" ] || unfinished+=("uncommitted changes")
[ "$(commits_ahead "$worktree" '@{upstream}' origin/HEAD origin/main)" -eq 0 ] || unfinished+=("unpushed commits")
if [ "$started" -gt 0 ] && [ "$state" = NONE ]; then
  unfinished+=("no open pull request")
fi
if [ -n "$issue" ] && (cd "$worktree" && gh issue view "$issue" --json body) | jq -e '.body | test("(?m)^\\s*- \\[ \\]")' >/dev/null; then
  unfinished+=("unticked acceptance criteria on issue #$issue")
fi

[ ${#unfinished[@]} -gt 0 ] || exit 0
list=$(printf '%s, ' "${unfinished[@]}")
list=${list%, }
refuse "$(git -C "$worktree" rev-parse HEAD) $list" \
  "This branch has $list. Keep working. If you cannot get past a problem, say what is blocking it." \
  "Stopped with unfinished work on this branch: $list."
