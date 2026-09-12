#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: check-citations.sh <ledger.json>

Compares every citation in a claim ledger with the source it names, with no
model taking part. Exits 0 when every citation passes, 1 when any fails, and 70
when a source could not be read.
See ~/.claude/rules/claim-checking.md.
USAGE
  exit 64
}

[ $# -eq 1 ] || usage

ledger=$1
[ -r "$ledger" ] ||
  { echo "check-citations.sh: $ledger cannot be read, so nothing was checked" >&2; exit 70; }

jq -e . "$ledger" >/dev/null 2>&1 ||
  { echo "check-citations.sh: $ledger is not readable as a ledger, so nothing was checked" >&2; exit 70; }

failed=0
unchecked=0

draft=$(jq -r '.draft' "$ledger")
[ -r "$draft" ] ||
  { echo "check-citations.sh: the draft $draft cannot be read, so nothing was checked" >&2; exit 70; }

while IFS= read -r text; do
  if grep -Fq -- "$text" "$draft"; then
    printf 'pass  claim in the draft\n'
  else
    printf 'fail  claim not in the draft: %s\n' "$text"
    failed=1
  fi
done < <(jq -r '.claims[].text' "$ledger")

while IFS= read -r claim; do
  text=$(printf '%s' "$claim" | jq -r .text)
  if [ "$(printf '%s' "$claim" | jq '.evidence | length')" -eq 0 ]; then
    printf 'fail  claim with no evidence: %s\n' "$text"
    failed=1
    continue
  fi

  if [ "$(printf '%s' "$claim" | jq -r '.negative')" = "true" ] &&
     [ "$(printf '%s' "$claim" | jq '[.evidence[] | select(.kind != "search")] | length')" -ne 0 ]; then
    printf 'fail  negative claim resting on more than searches: %s\n' "$text"
    failed=1
  fi
done < <(jq -c '.claims[]' "$ledger")

while IFS= read -r citation; do
  commit=$(printf '%s' "$citation" | jq -r .commit)
  path=$(printf '%s' "$citation" | jq -r .path)
  from=$(printf '%s' "$citation" | jq -r .from)
  to=$(printf '%s' "$citation" | jq -r .to)
  quote=$(printf '%s' "$citation" | jq -r .quote)

  if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
    printf 'not checked  %s at %s\n' "$path" "$commit"
    unchecked=1
    continue
  fi

  if ! file_at_commit=$(git show "$commit:$path" 2>/dev/null); then
    printf 'fail  %s:%s-%s\n' "$path" "$from" "$to"
    failed=1
    continue
  fi

  source_lines=$(printf '%s\n' "$file_at_commit" | sed -n "${from},${to}p")

  if [ -n "$source_lines" ] && [ "$source_lines" = "$quote" ]; then
    printf 'pass  %s:%s-%s\n' "$path" "$from" "$to"
  else
    printf 'fail  %s:%s-%s\n' "$path" "$from" "$to"
    failed=1
  fi
done < <(jq -c '.claims[].evidence[] | select(.kind == "lines")' "$ledger")

while IFS= read -r citation; do
  ticket=$(printf '%s' "$citation" | jq -r .ticket)
  quote=$(printf '%s' "$citation" | jq -r .quote)
  repo=${ticket%%#*}
  number=${ticket##*#}

  if ! body=$(gh issue view "$number" --repo "$repo" --json body --jq .body 2>/dev/null); then
    printf 'not checked  criterion in %s\n' "$ticket"
    unchecked=1
    continue
  fi

  if printf '%s' "$body" | grep -Fq -- "$quote"; then
    printf 'pass  criterion in %s\n' "$ticket"
  else
    printf 'fail  criterion not in %s: %s\n' "$ticket" "$quote"
    failed=1
  fi
done < <(jq -c '.claims[].evidence[] | select(.kind == "criterion")' "$ledger")

while IFS= read -r citation; do
  run=$(printf '%s' "$citation" | jq -r .run)
  recorded=$(printf '%s' "$citation" | jq -r .output)

  case "$run" in
    "sed -i"*|*" -delete"*|*" -exec"*)
      printf 'fail  command changes a file, so it was not run: %s\n' "$run"
      failed=1
      continue
      ;;
  esac

  case "$run" in
    "git show "*|"git log "*|"git cat-file "*|"git grep "*|"git status"*) ;;

    "gh issue view "*|"gh pr view "*|"gh api "*) ;;
    "grep "*|"rg "*|"sed "*|"awk "*|"cat "*|"head "*|"tail "*|"wc "*|"ls "*|"find "*|"jq "*) ;;
    *)
      printf 'fail  command is not a reader, so it was not run: %s\n' "$run"
      failed=1
      continue
      ;;
  esac

  again=$(eval "$run" 2>/dev/null) || again=""

  if [ "$again" = "$recorded" ]; then
    printf 'pass  command: %s\n' "$run"
  else
    printf 'fail  command output differs: %s\n' "$run"
    failed=1
  fi
done < <(jq -c '.claims[].evidence[] | select(.kind == "command")' "$ledger")

while IFS= read -r citation; do
  run=$(printf '%s' "$citation" | jq -r .run)
  looked_for=$(printf '%s' "$citation" | jq -r '.looked_for // ""')

  if [ -z "$looked_for" ]; then
    printf 'fail  search does not say what it looked for: %s\n' "$run"
    failed=1
    continue
  fi

  case "$run" in
    "git grep "*|"git log "*|"grep "*|"rg "*|"find "*|"jq "*|"ls "*) ;;
    *)
      printf 'fail  search is not a reader, so it was not run: %s\n' "$run"
      failed=1
      continue
      ;;
  esac

  found=$(eval "$run" 2>/dev/null) || found=""

  if [ -z "$found" ]; then
    printf 'pass  search came back empty: %s\n' "$looked_for"
  else
    printf 'fail  search now finds something: %s\n' "$looked_for"
    failed=1
  fi
done < <(jq -c '.claims[].evidence[] | select(.kind == "search")' "$ledger")

while IFS= read -r citation; do
  url=$(printf '%s' "$citation" | jq -r .url)
  quote=$(printf '%s' "$citation" | jq -r .quote)

  if ! page=$(curl -fsSL --max-time 20 "$url" 2>/dev/null); then
    printf 'not checked  link %s\n' "$url"
    unchecked=1
    continue
  fi

  if printf '%s' "$page" | grep -Fq -- "$quote"; then
    printf 'pass  link %s\n' "$url"
  else
    printf 'fail  link no longer holds the quote: %s\n' "$url"
    failed=1
  fi
done < <(jq -c '.claims[].evidence[] | select(.kind == "link")' "$ledger")

[ "$unchecked" -eq 0 ] || exit 70
[ "$failed" -eq 0 ] || exit 1
