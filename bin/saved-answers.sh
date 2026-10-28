#!/usr/bin/env bash
set -euo pipefail

answers_dir=${SYMPHONY_ANSWERS_DIR:-"$(cd "$(dirname "$0")/.." && pwd)/rules/answers"}

words=$(printf '%s\n' "$*" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | jq -R . | jq -sc 'map(select(length > 0))')

jq -r --argjson words "$words" '
  def words: ascii_downcase | [scan("[[:alnum:]]+")];
  .answers[]
  | select((.question | words) - ((.question | words) - $words) | length > 0)
  | "default: \(.question)\n\(.answer)"
' "$answers_dir/defaults.json"
