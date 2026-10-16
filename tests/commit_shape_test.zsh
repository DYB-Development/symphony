#!/usr/bin/env zsh
# Tests for bin/commit-shape.sh. Each case runs against a stubbed `gh` that
# answers from files written for the case, and a stubbed `claude`.
#
# Usage: zsh tests/commit_shape_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SHAPE="$SCRIPT_DIR/../bin/commit-shape.sh"

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

new_case() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/commit_shape_test.XXXXXX")"
  mkdir -p "$WORK/bin" "$WORK/commits" "$WORK/repo"
  : > "$WORK/commits/order"
  cat > "$WORK/bin/gh" <<SH
#!/usr/bin/env bash
case "\$2" in
  repos/acme/quotes/pulls/7/commits) cat "$WORK/commits/order" ;;
  repos/acme/quotes/commits/*)
    sha=\${2#repos/acme/quotes/commits/}
    case "\$*" in
      *.files*) cat "$WORK/commits/\$sha.files" ;;
      *.commit.message*) cat "$WORK/commits/\$sha.message" ;;
      *diff*) cat "$WORK/commits/\$sha.diff" ;;
    esac ;;
esac
SH
  chmod +x "$WORK/bin/gh"
  cat > "$WORK/bin/claude" <<SH
#!/usr/bin/env bash
cat > "$WORK/asked"
printf '%s\n' "\${CLAUDE_REPLY:-Exception: neither}"
SH
  chmod +x "$WORK/bin/claude"
  DRAFT_FILE="$WORK/repo/.review-7.json"
  RESULT="$WORK/repo/.review-7.commits.json"
}

drop_case() {
  rm -rf "$WORK"
}

add_commit() {
  local sha="$1" message="$2"
  shift 2
  printf '%s\n' "$sha" >> "$WORK/commits/order"
  printf '%s\n' "$message" > "$WORK/commits/$sha.message"
  printf '%s\n' "$@" > "$WORK/commits/$sha.files"
  printf 'diff --git a/%s b/%s\n+changed\n' "$1" "$1" > "$WORK/commits/$sha.diff"
}

shape() {
  PATH="$WORK/bin:$PATH" SYMPHONY_AGENT_MODELS_FILE="$WORK/no-models.json" "$SHAPE" acme/quotes 7 "$DRAFT_FILE"
}

echo "commit-shape.sh:"

new_case
add_commit c1 "Add the quote total" app/models/quote.rb
shape >/dev/null 2>&1
assert_equals "c1 flagged" "$(jq -r '.commits[] | "\(.sha) \(.shape)"' "$RESULT" 2>/dev/null)" \
  "flags a commit that holds code and no test, in a file beside the review draft"
drop_case

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
