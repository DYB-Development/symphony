#!/usr/bin/env bash
set -euo pipefail

address=$1
label=$2

[ -s .work ] && jq -se --arg address "$address" 'any(.address == $address)' .work >/dev/null && exit 0

jq -nc --arg address "$address" --arg label "$label" '{address: $address, label: $label}' >> .work
