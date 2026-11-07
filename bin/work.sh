#!/usr/bin/env bash
set -euo pipefail

address=$1
label=$2

jq -nc --arg address "$address" --arg label "$label" '{address: $address, label: $label}' >> .work
