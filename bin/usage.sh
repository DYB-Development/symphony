#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh
       usage.sh --render

Totals the tokens the session transcripts recorded for this repo on the current
branch, broken down by input, output and cache. `--render` prints the PR body's
Tokens Used section from those totals, and says `Not measured.` when no
transcript names this branch.
Transcripts are read from $CLAUDE_CONFIG_DIR/projects, or ~/.claude/projects.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

case "${1:-}" in
  "" | --render) ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel) || {
  echo "usage.sh: not inside a git repository" >&2
  exit 69
}

branch=$(git branch --show-current)
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

read_transcripts() {
  local transcript
  while IFS= read -r transcript; do
    jq -r --arg branch "$branch" --arg root "$root" '
      select(type == "object")
      | select(.type == "assistant")
      | select(.gitBranch == $branch)
      | select((.cwd // "") == $root or ((.cwd // "") | startswith($root + "/")))
      | [
          .message.id,
          (.message.usage.input_tokens // 0),
          (.message.usage.output_tokens // 0),
          (.message.usage.cache_read_input_tokens // 0),
          (.message.usage.cache_creation_input_tokens // 0)
        ]
      | @tsv' "$transcript" 2>/dev/null || true
  done < <(find "$projects" -type f -name '*.jsonl' 2>/dev/null)
}

total_tokens() {
  awk -F '\t' '
    function grouped(number,   digits, out) {
      digits = sprintf("%d", number)
      while (length(digits) > 3) {
        out = "," substr(digits, length(digits) - 2) out
        digits = substr(digits, 1, length(digits) - 3)
      }
      return digits out
    }
    !counted[$1]++ { input += $2; output += $3; read += $4; written += $5 }
    END {
      if (length(counted) == 0) exit
      printf "Input: %s\n", grouped(input)
      printf "Output: %s\n", grouped(output)
      printf "Cache read: %s\n", grouped(read)
      printf "Cache write: %s\n", grouped(written)
      printf "Total: %s\n", grouped(input + output + read + written)
    }
  '
}

totals=$(read_transcripts | total_tokens)

if [ "${1:-}" = "--render" ]; then
  printf '## Tokens Used\n\n'
  if [ -n "$totals" ]; then
    printf '%s\n' "$totals" | sed 's/^/- /'
  else
    printf 'Not measured.\n'
  fi
  exit 0
fi

printf '%s\n' "${totals:-No tokens recorded for this branch.}"
