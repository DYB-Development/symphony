#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: usage.sh
       usage.sh --render
       usage.sh --runs
       usage.sh --rows

Totals the tokens the session transcripts recorded for this branch, broken down
by input, output and cache. `--render` prints the PR body's Tokens Used section
from those totals, and says `Not measured.` when no transcript names this
branch. `--runs` lists every scribe run recorded for this clone instead, oldest
first, each with the branch it worked on and what it cost, whichever branch is
checked out now. `--rows` prints what the owner put into this branch instead,
one row per measure, oldest first, as the time, the session, the kind of
measure and its amount, separated by tabs.
A message is charged to the branch the worktree it was working in held when it
was recorded, read from that worktree's own reflog. The worktree comes from the
absolute paths in that agent run's own tool records, carried forward to the
messages after them, so two agents running at once are never charged for each
other's tokens.
Transcripts are read from the directories under $CLAUDE_CONFIG_DIR/projects, or
~/.claude/projects, whose names carry a path of this clone, and from all of them
when none does.
See ~/.claude/rules/pr-body.md.
USAGE
  exit 64
}

case "${1:-}" in
  "" | --render | --runs | --rows) ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel) || {
  echo "usage.sh: not inside a git repository" >&2
  exit 69
}

branch=$(git branch --show-current)
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

work=$(mktemp -d "${TMPDIR:-/tmp}/usage.XXXXXX")
trap 'rm -rf "$work"' EXIT

worktrees="$work/worktrees"
timelines="$work/timelines"

write_worktrees() {
  {
    printf '%s\n' "$root"
    git worktree list --porcelain | sed -n 's/^worktree //p'
  } | sort -u | awk 'NF { print length($0), $0 }' | sort -rn -k1,1 | cut -d' ' -f2-
}

write_timelines() {
  local worktree checkouts
  while IFS= read -r worktree; do
    [ -d "$worktree" ] || continue
    checkouts=$({ git -C "$worktree" reflog show --date=unix HEAD 2>/dev/null || true; } |
      sed -nE 's/^[^ ]+ HEAD@\{([0-9]+)\}: checkout: moving from (.+) to (.+)$/\1 \2 \3/p')
    if [ -z "$checkouts" ]; then
      printf '%s\t0\t%s\n' "$worktree" "$(git -C "$worktree" branch --show-current)"
      continue
    fi
    printf '%s\n' "$checkouts" | awk -v worktree="$worktree" '
      { at[NR] = $1; from[NR] = $2; to[NR] = $3 }
      END {
        printf "%s\t0\t%s\n", worktree, from[NR]
        for (entry = NR; entry >= 1; entry--) printf "%s\t%s\t%s\n", worktree, at[entry], to[entry]
      }'
  done < "$worktrees"
}

write_worktrees > "$worktrees"
write_timelines > "$timelines"

transcript_dirs() {
  local worktree named found=''
  while IFS= read -r worktree; do
    named=$(find "$projects" -maxdepth 1 -type d \
      -name "*$(printf '%s' "$worktree" | tr -c 'a-zA-Z0-9' '-')*" 2>/dev/null) || named=''
    [ -n "$named" ] && found+="$named"$'\n'
  done < "$worktrees"
  if [ -n "$found" ]; then
    printf '%s' "$found" | sort -u
  else
    printf '%s\n' "$projects"
  fi
}

transcript_files() {
  local patterns=() worktree
  while IFS= read -r worktree; do patterns+=(-e "$worktree"); done < "$worktrees"
  transcript_dirs | grep -v '^$' | tr '\n' '\0' |
    xargs -0 grep -rlF --include='*.jsonl' "${patterns[@]}" 2>/dev/null || true
}

extract=$(cat <<'JQ'
def stamp:
  if . == null or . == "" then 0
  else (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch 0)
  end;

def worked_paths:
  if .type == "assistant" then
    [ .message.content // [] | .[]? | select(.type? == "tool_use") | .input
      | ( ((.command // "") | scan("(?:^|[;&|(\\s])(?:cd|-C)\\s+([^\\s;&|)'\"]+)")),
          (.file_path // empty) ) ]
  else
    [ (.toolUseResult | if type == "object" then (.bashEditDiff.files // [])[]?.filePath else empty end) ]
  end
  | flatten
  | map(select(type == "string"));

def typed_prompt:
  .type == "user"
  and (.isSidechain | not)
  and (.agentId == null)
  and (.isMeta | not)
  and (.message.content | type == "string")
  and (.message.content | test("^\\s*(<task-notification>|<local-command-|<bash-std|Another Claude session sent a message|This session is being continued)") | not);

def words:
  [ scan("\\S+") ] | length;

def pasted_blocks:
  [ match("<pasted_content[^>]*>([\\s\\S]*?)</pasted_content[^>]*>"; "g") | .captures[0].string ];

def effort:
  if typed_prompt then
    { kind: "prompt", amount: 1 },
    { kind: "typed", amount: (.message.content | words) },
    { kind: "pasted", amount: ([ .message.content | scan("<pasted_content[ >]") ] | length) },
    { kind: "pasted-words", amount: (.message.content | pasted_blocks | map(words) | add // 0) }
  else empty end;

def row($id; $kind; $amount):
  [ $id,
    (.timestamp | stamp),
    (.cwd // ""),
    (.agentId // ""),
    (.attributionAgent // ""),
    (.message.usage.input_tokens // 0),
    (.message.usage.output_tokens // 0),
    (.message.usage.cache_read_input_tokens // 0),
    (.message.usage.cache_creation_input_tokens // 0),
    (worked_paths | join("|")),
    $kind,
    $amount,
    (.sessionId // "")
  ]
  | @tsv;

select(type == "object")
| select(.type == "assistant" or .type == "user")
| . as $entry
| if .type == "assistant" then row(.message.id // ""; "tokens"; 0) else row(""; ""; 0) end,
  (effort | . as $effort | $entry | row("\(.uuid // ""):\($effort.kind)"; $effort.kind; $effort.amount))
JQ
)

attribute=$(cat <<'AWK'
function under(path, directory) {
  return path == directory || substr(path, 1, length(directory) + 1) == directory "/"
}

function worktree_of(path,   index_) {
  for (index_ = 1; index_ <= worktrees; index_++)
    if (under(path, worktree[index_])) return worktree[index_]
  return ""
}

function branch_at(place, moment,   index_, held) {
  held = ""
  for (index_ = 1; index_ <= entries[place]; index_++)
    if (at[place, index_] <= moment) held = branch[place, index_]
  return held
}

BEGIN {
  FS = OFS = "\t"
  while ((getline line < worktrees_file) > 0)
    if (line != "") worktree[++worktrees] = line
  close(worktrees_file)
  while ((getline line < timelines_file) > 0) {
    if (line == "") continue
    split(line, field, "\t")
    place = field[1]
    index_ = ++entries[place]
    at[place, index_] = field[2] + 0
    branch[place, index_] = field[3]
  }
  close(timelines_file)
}

{
  found = ""
  if ($10 != "") {
    count = split($10, named, "|")
    for (index_ = 1; index_ <= count; index_++) {
      found = worktree_of(named[index_])
      if (found != "") break
    }
  }

  home = worktree_of($3)
  if (found != "") working = found
  else if (home == "") next
  else if (working == "") working = home

  if ($1 == "" || working == "") next

  print $1, branch_at(working, $2 + 0), $4, $5, $6, $7, $8, $9, $2, $11, $12, $13
}
AWK
)

attributed() {
  local transcript
  while IFS= read -r transcript; do
    jq -r "$extract" "$transcript" 2>/dev/null |
      awk -v worktrees_file="$worktrees" -v timelines_file="$timelines" "$attribute" || true
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

total_tokens() {
  awk -F '\t' -v branch="$branch" "$grouped"'
    $2 == branch && $10 == "tokens" && !counted[$1]++ { input += $5; output += $6; read += $7; written += $8 }
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

list_runs() {
  sort -t $'\t' -k9,9n | awk -F '\t' "$grouped"'
    $4 != "" && $10 == "tokens" && !counted[$1]++ {
      run = $3
      if (!(seen[run]++)) order[++runs] = run
      type[run] = $4
      spent = $5 + $6 + $7 + $8
      total[run] += spent
      on[run, $2] += spent
      if (on[run, $2] > most[run]) { most[run] = on[run, $2]; branch[run] = $2 }
    }
    END {
      for (index_ = 1; index_ <= runs; index_++) {
        run = order[index_]
        printf "%s — %s — %s\n", type[run], branch[run], grouped(total[run])
      }
    }
  '
}

list_rows() {
  awk -F '\t' -v branch="$branch" '
    BEGIN { OFS = "\t" }
    $2 == branch && $10 != "tokens" && $10 != "" && !counted[$1]++ { print $9, $12, $10, $11 }
  ' | sort -t $'\t' -k1,1n -s
}

if [ "${1:-}" = "--rows" ]; then
  attributed | list_rows
  exit 0
fi

if [ "${1:-}" = "--runs" ]; then
  runs=$(attributed | list_runs)
  printf '%s\n' "${runs:-No scribe runs recorded for this repo.}"
  exit 0
fi

totals=$(attributed | total_tokens)

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
