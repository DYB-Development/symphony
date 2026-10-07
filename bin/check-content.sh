#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: check-content.sh <rules.json> [<root>]

Checks every rule in a list of rules. A rule names a file, relative to the root
unless it is absolute, and text that must be in it ("contains") or must not be
("absent"). Every failing rule is reported, and the exit code is non-zero when
any rule fails.
USAGE
  exit 64
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage

rules=$1
root=${2:-.}

path_of() {
  case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$root" "$1" ;; esac
}

printf 'Checked against rules version %s\n' "$(jq -r '.version' "$rules")"

failed=0
while IFS=$'\037' read -r file contains absent; do
  content=$(cat "$(path_of "$file")" 2>/dev/null || true)
  if [ -n "$contains" ] && [[ "$content" != *"$contains"* ]]; then
    printf 'FAIL %s is missing "%s"\n' "$file" "$contains"
    failed=1
  fi
  if [ -n "$absent" ] && [[ "$content" == *"$absent"* ]]; then
    failed=1
  fi
done < <(jq -r '.rules[] | [.file, (.contains // ""), (.absent // "")] | join("\u001f")' "$rules")

exit "$failed"
