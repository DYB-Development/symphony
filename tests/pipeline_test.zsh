#!/usr/bin/env zsh
# Tests for bin/pipeline.sh. Every case runs against a stub curl that answers
# each hub method from files the case writes and records each call, a stub gh,
# a throwaway settings folder and a throwaway git repo, so nothing reaches
# dyb_web or GitHub.
#
# Usage: zsh tests/pipeline_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
PIPELINE="$SCRIPT_DIR/../bin/pipeline.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      expected: %s\n' "${(qqq)expected}"
    printf '      actual:   %s\n' "${(qqq)actual}"
  fi
}

setup() {
  WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pipeline_test.XXXXXX")" && pwd -P)"
  mkdir -p "$WORK/bin" "$WORK/answers" "$WORK/settings" "$WORK/repo"
  printf 'url=https://dyb.example\ntoken=secret\n' > "$WORK/settings/dyb_web"
  export SYMPHONY_CONFIG_DIR="$WORK/settings" SYMPHONY_SESSION="session-a"
  cat > "$WORK/bin/curl" <<STUB
#!/usr/bin/env bash
[ -z "\${STUB_CURL_DOWN:-}" ] || exit 7
url="" data="" method=GET
while [ \$# -gt 0 ]; do
  case "\$1" in
    -X) method="\$2"; shift ;;
    -d|--data) data="\$2"; method=POST; shift ;;
    http*) url="\$1" ;;
  esac
  shift
done
name="\${url##*/}"; name="\${name%%\\?*}"
printf '%s %s %s\\n' "\$method" "\$name" "\$data" >> "$WORK/calls"
count=\$(( \$(cat "$WORK/count.\$name" 2>/dev/null || echo 0) + 1 ))
echo "\$count" > "$WORK/count.\$name"
answer="$WORK/answers/\$name.\$count"
[ -f "\$answer" ] || answer="$WORK/answers/\$name"
printf '%s\\n%s' "\$(cat "\$answer" 2>/dev/null || echo '{"answer":null}')" "\$(cat "$WORK/answers/\$name.code" 2>/dev/null || echo 200)"
STUB
  chmod +x "$WORK/bin/curl"
  path=("$WORK/bin" $path)
  git -C "$WORK/repo" init -q
  cd "$WORK/repo"
}

teardown() {
  cd "$SCRIPT_DIR"
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
  unset SYMPHONY_CONFIG_DIR SYMPHONY_SESSION STUB_CURL_DOWN
}

answer() { printf '%s' "$2" > "$WORK/answers/$1"; }

step() {
  jq -nc --arg id "$1" --arg name "$2" --arg kind "$3" --arg script "${4:-}" \
    '{answer: {id: $id, name: $name, kind: $kind, script: $script, agent: "builder", model: "claude-sonnet-5-5",
      work: {title: "Export quotes", request: "Reps want quotes as CSV", acceptance_criteria: "A rep downloads a CSV", repo: "acme/quotes"}}}'
}

setup
answer claim_work_item '{"answer":7}'
answer current_step "$(step check "Run work-check" script work-check)"
assert_equals "Claimed Export quotes
First step: Run work-check" "$("$PIPELINE" claim 7)" "claiming a work item by its id prints its title and its first step"
teardown

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
