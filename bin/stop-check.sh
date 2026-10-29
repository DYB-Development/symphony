#!/usr/bin/env bash
set -euo pipefail

reason="This turn ends by asking the owner something in plain text, and nothing tells the owner a question is waiting. Keep working on the task you were given. If you truly need the owner to decide something before you can go on, ask in a question window with AskUserQuestion and lay out the options."

cat >/dev/null
jq -nc --arg reason "$reason" '{decision: "block", reason: $reason}'
