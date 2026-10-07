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
