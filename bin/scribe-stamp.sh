#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: scribe-stamp.sh pr|issue "<model-id>"
       scribe-stamp.sh plan|review|audit "<model-id>" [<owner/repo>@<sha>]

The model must be its identifier, not its display name — `claude-opus-5[1m]`,
never `Opus 5 (1M context)`. A stamp is only worth reading if every scribe
spells the same model the same way.

A plan, a review and an audit are claims about a repo at one commit, so their
stamps name it below the rest, after a blank line — `Planned Against` for a plan,
`Reviewed Against` for a review, `Audited Against` for an audit. With no source
given it is read from the working directory's repository, and a `+` there means
the tree was dirty. A review passes the pull request's head commit instead, since
that is the code it read. `pr` and `issue` carry neither line and refuse a
source.

Prints the version stamp a scribe appends below the body's last trailer,
naming the commit that last touched each prompt and rules file it followed. It
refuses rather than printing an empty version when a file it names is missing or
uncommitted, since a stamp nobody can trace back is worse than none.
See ~/.claude/rules/pr-body.md, ~/.claude/rules/issue-schema.md,
~/.claude/rules/feature-plan.md and ~/.claude/rules/pr-review.md.
USAGE
  exit 64
}

[ $# -eq 2 ] || [ $# -eq 3 ] || usage

kind=$1
model=$2
source=${3:-}

printf '%s' "$model" | grep -qE '^[a-z0-9][a-z0-9.-]*(\[[a-z0-9]+\])?$' || usage

[ -z "$source" ] ||
  printf '%s' "$source" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+@[0-9a-f]{7,40}$' || usage

root=${SCRIBE_STAMP_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

case "$kind" in
  pr)     scribe=pr-scribe;     rules=(pr-body writing-style); [ -z "$source" ] || usage ;;
  issue)  scribe=issue-scribe;  rules=(issue-schema writing-style); [ -z "$source" ] || usage ;;
  plan)   scribe=plan-scribe;   rules=(feature-plan review-checks writing-style) ;;
  review) scribe=review-scribe; rules=(review-checks pr-review writing-style) ;;
  audit)  scribe=audit-scribe;  rules=(repo-audit review-checks audit-rubric.json writing-style) ;;
  *)      usage ;;
esac

rules_path() {
  case "$1" in
    *.*) printf 'rules/%s' "$1" ;;
    *)   printf 'rules/%s.md' "$1" ;;
  esac
}

# Every file this stamp names has to be there and committed, or the stamp is
# untraceable and says so instead of printing an empty version.
check() {
  [ -e "$root/$1" ] ||
    { echo "scribe-stamp.sh: $1 is named by this stamp and is not there" >&2; exit 70; }
  [ -n "$(git -C "$root" log -1 --format=%h -- "$1")" ] ||
    { echo "scribe-stamp.sh: $1 is named by this stamp and has never been committed" >&2; exit 70; }
}

check "agents/$scribe.md"
for rule in "${rules[@]}"; do check "$(rules_path "$rule")"; done

version() {
  local sha
  sha=$(git -C "$root" log -1 --format=%h -- "$1")
  [ -z "$(git -C "$root" status --porcelain -- "$1")" ] || sha="$sha+"
  printf '%s' "$sha"
}

printf '## Generation Metadata\n\n'

printf "Scribe: %s \`%s\`\n" "$scribe" "$(version "agents/$scribe.md")"

rules_line=""
for rule in "${rules[@]}"; do
  case "$rule" in
    *.*) name=${rule%.*} ;;
    *)   name=$rule ;;
  esac
  rules_line+="${rules_line:+, }$name \`$(version "$(rules_path "$rule")")\`"
done
printf 'Rules: %s\n' "$rules_line"

cli=$(printf '%s' "${AI_AGENT:-}" | sed -nE 's/^claude-code_([0-9-]+)_.*/\1/p' | tr '-' '.')
[ -n "$cli" ] || cli=$(claude --version 2>/dev/null | awk '{ print $1 }' || true)

printf "Model: \`%s\`, cc \`%s\`\n" "$model" "${cli:-unknown}"

case "$kind" in
  plan|review|audit)
    if [ -z "$source" ]; then
      origin=$(git remote get-url origin 2>/dev/null || true)
      repo=$(printf '%s' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')
      sha=$(git rev-parse --short HEAD)
      [ -z "$(git status --porcelain)" ] || sha="$sha+"
      source="$repo@$sha"
    fi
    case "$kind" in
      plan)   label="Planned Against" ;;
      review) label="Reviewed Against" ;;
      audit)  label="Audited Against" ;;
    esac
    printf '\n%s: `%s`\n' "$label" "$source"
    ;;
esac
