#!/usr/bin/env bash
set -euo pipefail

address=$1
label=$2

root=$(git rev-parse --show-toplevel) || {
  echo "work.sh: not inside a git repository" >&2
  exit 69
}

file="$root/.work"

[ -s "$file" ] && jq -se --arg address "$address" 'any(.address == $address)' "$file" >/dev/null && exit 0

jq -nc --arg address "$address" --arg label "$label" '{address: $address, label: $label}' >> "$file"
