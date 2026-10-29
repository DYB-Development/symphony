#!/usr/bin/env bash
set -euo pipefail

reason="This turn ends by asking the owner something in plain text, and nothing tells the owner a question is waiting. Keep working on the task you were given. If you truly need the owner to decide something before you can go on, ask in a question window with AskUserQuestion and lay out the options."

last_text() {
  jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text")] | last | .text // empty' "$1"
}

closing_lines() {
  grep -v '^[[:space:]]*$' | tail -n 3
}

asks() {
  grep -Eiq -e '\?[*_"'\'')]*([[:space:]]|$)' \
    -e '(^|[^[:alnum:]])(do you want|should i|shall i|want me to|would you like|let me know|tell me if)([^[:alnum:]]|$)'
}

transcript=$(jq -r '.transcript_path // empty')
last_text "$transcript" | closing_lines | asks || exit 0
jq -nc --arg reason "$reason" '{decision: "block", reason: $reason}'
