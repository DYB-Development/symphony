#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh
       usage.sh --render
       usage.sh --runs

Totals the tokens the session transcripts recorded for this repo on the current
branch, broken down by input, output and cache. `--render` prints the PR body's
Tokens Used section from those totals, and says `Not measured.` when no
transcript names this branch. `--runs` lists every scribe run recorded for this
repo instead, oldest first, each with the branch it ran on and what it cost,
whichever branch is checked out now.
Transcripts are read from the directories under $CLAUDE_CONFIG_DIR/projects, or
~/.claude/projects, whose names carry this repo's path, and from all of them when
none does.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

case "${1:-}" in
  "" | --render | --runs) ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel) || {
  echo "usage.sh: not inside a git repository" >&2
  exit 69
}

branch=$(git branch --show-current)
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

transcript_dirs() {
  local named
  named=$(find "$projects" -maxdepth 1 -type d -name "*${root//\//-}*" 2>/dev/null)
  printf '%s\n' "${named:-$projects}"
}

transcript_files() {
  transcript_dirs | tr '\n' '\0' | xargs -0 grep -rlF --include='*.jsonl' "$root" 2>/dev/null
}

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
  done < <(transcript_files)
}

grouped='
  function grouped(number,   digits, out) {
    digits = sprintf("%d", number)
    while (length(digits) > 3) {
      out = "," substr(digits, length(digits) - 2) out
      digits = substr(digits, 1, length(digits) - 3)
    }
    return digits out
  }
'

read_runs() {
  local transcript
  while IFS= read -r transcript; do
    jq -r --arg root "$root" '
      select(type == "object")
      | select(.type == "assistant")
      | select((.attributionAgent // "") != "")
      | select((.cwd // "") == $root or ((.cwd // "") | startswith($root + "/")))
      | [
          (.timestamp // ""),
          .agentId,
          .attributionAgent,
          (.gitBranch // ""),
          .message.id,
          (.message.usage.input_tokens // 0),
          (.message.usage.output_tokens // 0),
          (.message.usage.cache_read_input_tokens // 0),
          (.message.usage.cache_creation_input_tokens // 0)
        ]
      | @tsv' "$transcript" 2>/dev/null || true
  done < <(transcript_files)
}

list_runs() {
  sort -k1,1 | awk -F '\t' "$grouped"'
    !counted[$5]++ {
      if (!(seen[$2]++)) order[++runs] = $2
      type[$2] = $3
      branch[$2] = $4
      total[$2] += $6 + $7 + $8 + $9
    }
    END {
      for (index_ = 1; index_ <= runs; index_++) {
        run = order[index_]
        printf "%s — %s — %s\n", type[run], branch[run], grouped(total[run])
      }
    }
  '
}

total_tokens() {
  awk -F '\t' "$grouped"'
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

if [ "${1:-}" = "--runs" ]; then
  runs=$(read_runs | list_runs)
  printf '%s\n' "${runs:-No scribe runs recorded for this repo.}"
  exit 0
fi

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
