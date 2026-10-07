#!/usr/bin/env zsh
# Tests for bin/tick-criterion.sh. Every case runs against a stub gh that serves
# one issue body and writes down the body it is asked to save, so nothing
# reaches GitHub.
#
# Usage: zsh tests/tick_criterion_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
TICK="$SCRIPT_DIR/../bin/tick-criterion.sh"

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

BODY=$'## Part of\n- [ ] not a criterion\n\n## Acceptance criteria\n- [ ] A rep can quote.\n- [x] A rep can save.\n- [ ] A rep can send.\n\n## Out of scope\n- [ ] not a criterion either'

# A gh that serves $BODY for issue 12 of acme/widget and keeps any body it is
# asked to save in $WORK/saved.
stub_gh() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/tick_criterion_test.XXXXXX")"
  mkdir -p "$WORK/bin"
  printf '%s' "$BODY" > "$WORK/body"
  cat > "$WORK/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$*" in
  "api repos/acme/widget/issues/12 --jq .body") cat "$WORK/body" ;;
  "api -X PATCH repos/acme/widget/issues/12 -F body=@-"*) cat > "$WORK/saved" ;;
esac
STUB
  chmod +x "$WORK/bin/gh"
  path=("$WORK/bin" $path)
}

drop_stub() {
  path=(${path:#$WORK/bin})
  rm -rf "$WORK"
}

echo "tick-criterion.sh:"

stub_gh
"$TICK" acme/widget 12 3 >/dev/null 2>&1
assert_equals "${BODY/- \[ \] A rep can send./- [x] A rep can send.}" "$(cat "$WORK/saved" 2>/dev/null)" \
  "ticks the criterion at that position and leaves every other line unchanged"
drop_stub

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
