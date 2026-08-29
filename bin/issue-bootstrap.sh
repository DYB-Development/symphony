#!/usr/bin/env bash
#
# issue-bootstrap.sh — materialize the issue schema into a repo.
# Creates the label set and (optionally) writes .github/ISSUE_TEMPLATE/* so
# GitHub renders the web "New issue" forms. Idempotent: re-running updates labels
# in place (gh label --force) and overwrites templates.
# Schema source of truth: rules/issue-schema.md
#
# Usage:
#   issue-bootstrap.sh                 # bootstrap the repo in the current dir
#   issue-bootstrap.sh --labels-only   # skip writing .github templates
#   issue-bootstrap.sh --all-repos     # labels ONLY, across every repo you own
#                                       # (the rare "schema changed" sync; no PRs)
#
set -euo pipefail

# Accounts whose repos get the schema, for --all-repos only. Set
# ISSUE_BOOTSTRAP_OWNERS to a space-separated list of the accounts and orgs you
# own. It is deliberately empty by default: --all-repos writes to every
# non-archived repo of every account named here, so nothing is named for you.
read -r -a OWNERS <<< "${ISSUE_BOOTSTRAP_OWNERS:-}" 

MODE="repo"
case "${1:-}" in
  --all-repos)   MODE="all" ;;
  --labels-only) MODE="labels" ;;
esac

command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }

# label NAME COLOR DESC [REPO]   — REPO omitted = current-dir repo
label() {
  local repo_arg=()
  [[ -n "${4:-}" ]] && repo_arg=(--repo "$4")
  # ${arr[@]+"${arr[@]}"} guards the empty-array expansion: bash 3.2 (macOS
  # system bash) treats "${arr[@]}" as an unbound variable under `set -u`.
  gh label create "$1" -c "$2" -d "$3" --force ${repo_arg[@]+"${repo_arg[@]}"} >/dev/null
}

# create the full schema label set in $1 (or current repo if empty)
seed_labels() {
  local r="${1:-}"
  # type (exactly one per issue) — pipeline order: request → plan → breakdown → task
  label "type:request"   "#bfe5bf" "A recorded request; a plan may be spun from it later" "$r"
  label "type:plan"      "#0e8a16" "The plan, written in the issue. NOT code" "$r"
  label "type:breakdown" "#5319e7" "Slices a plan into standalone task issues" "$r"
  label "type:task"      "#1d76db" "Standalone unit of executable work (next-task runs this)" "$r"
  label "type:bug"       "#d73a4a" "Defect" "$r"
  label "type:chore"     "#c5def5" "Maintenance/upkeep (deps, CI, lint)" "$r"
  label "type:spike"     "#fbca04" "Time-boxed research; output feeds a plan" "$r"
  # priority
  label "priority:high"   "#b60205" "Take first" "$r"
  label "priority:medium" "#e99695" "Normal" "$r"
  label "priority:low"    "#f9d0c4" "Backlog" "$r"
  # size
  label "size:s" "#ededed" "Quick" "$r"
  label "size:m" "#d4d4d4" "Moderate" "$r"
  label "size:l" "#bbbbbb" "Large" "$r"
  # status
  label "blocked"        "#000000" "Unmet dependency; next-task skips" "$r"
  label "needs-grooming" "#fef2c0" "Not yet standalone/ready" "$r"
}

# --- --all-repos: the rare schema-wide label sync (labels only, no PRs) -------
if [[ "$MODE" == "all" ]]; then
  if [[ ${#OWNERS[@]} -eq 0 ]]; then
    echo "issue-bootstrap.sh: --all-repos needs to know whose repos to sync." >&2
    echo "  Set ISSUE_BOOTSTRAP_OWNERS to the accounts you own, space separated." >&2
    exit 78
  fi
  for owner in "${OWNERS[@]}"; do
    echo "Syncing labels across $owner ..."
    gh repo list "$owner" --no-archived --limit 500 --json nameWithOwner -q '.[].nameWithOwner' \
    | while read -r repo; do
        echo "  $repo"
        seed_labels "$repo"
      done
  done
  echo "Done. (labels only — nothing committed, no PRs)"
  exit 0
fi

# --- single repo -------------------------------------------------------------
gh repo view >/dev/null 2>&1 || { echo "not in a GitHub repo (or gh not authed)" >&2; exit 1; }
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Bootstrapping issue schema on $REPO"
echo "Labels:"
seed_labels
echo "  (15 labels)"

if [[ "$MODE" == "labels" ]]; then
  echo "Done (labels only)."
  exit 0
fi

DIR=".github/ISSUE_TEMPLATE"
mkdir -p "$DIR"
echo "Templates → $DIR/"
write_tpl() { printf '%s\n' "$2" > "$DIR/$1"; echo "  $1"; }

write_tpl request.md '---
name: Request
about: Capture a raw request (a plan can be spun from it later)
labels: ["type:request"]
---

## Request
<!-- the raw request, in your words — capture it, do not polish it -->

## Why / what it could enable


## Next
Spin a `type:plan` from this when ready (or close if dropped).'

write_tpl plan.md '---
name: Plan
about: The plan, written in the issue itself (no committed doc, no code)
labels: ["type:plan"]
---

## Goal


## The plan
<!-- the actual design: options · tradeoffs · recommendation · risks — written out here -->

## Done when
- [ ] Plan reviewed/approved
- [ ] A `type:breakdown` slices it into standalone tasks
- [ ] Produces NO production code

## Dependencies
none'

write_tpl breakdown.md '---
name: Breakdown
about: Slice a plan into standalone task issues
labels: ["type:breakdown"]
---

## Source plan
<!-- link the type:plan issue -->

## Deliverable
N standalone `type:task` issues, prioritized, dependencies wired, linked back here.

## Done when
- [ ] Issues created and linked here
- [ ] This issue closed

## Dependencies
none'

write_tpl task.md '---
name: Task
about: Standalone unit of executable work
labels: ["type:task"]
---

**As a** ,
**I want** ,
**so that** .

## Part of
<!-- The feature group this is a unit of work in, one sentence. Or "standalone". -->

## Acceptance criteria
<!-- One user-observable behavior each. No file paths, no class names, no plan. -->
- [ ]

## Out of scope
-

## Dependencies
none'

write_tpl bug.md '---
name: Bug
about: A defect
labels: ["type:bug"]
---

## Context


## Steps to reproduce
1.

## Expected vs actual


## Acceptance criteria
- [ ] Fix + regression test

## Dependencies
none'

echo "Done."
