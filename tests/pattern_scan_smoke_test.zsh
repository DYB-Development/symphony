#!/usr/bin/env zsh
# Runs the pattern scan with the packs this package ships, adds its hits to a
# draft, and renders the draft, against a stubbed `gh` that prints one diff.
#
# Usage: zsh tests/pattern_scan_smoke_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCAN="$SCRIPT_DIR/../bin/pattern-scan.sh"
DRAFT="$SCRIPT_DIR/../bin/review-draft.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "pattern scan into a rendered draft:"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pattern_scan_smoke_test.XXXXXX")"
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
cat <<'DIFF'
diff --git a/config/payments.rb b/config/payments.rb
--- a/config/payments.rb
+++ b/config/payments.rb
@@ -1,1 +1,2 @@
 module Payments
+  API_KEY = "q8Zr2mWx7pLk4vNt9sYbHj3c"
DIFF
SH
chmod +x "$WORK/bin/gh"

PATH="$WORK/bin:$PATH" "$SCAN" acme/quotes 7 "$WORK/.review-7.json" &&
  "$DRAFT" --add-scan "$WORK/.review-7.json" "$WORK/.review-7.scan.json"
rendered="$("$DRAFT" --render "$WORK/.review-7.json")"

if [[ "$rendered" == *"1. config/payments.rb:2 (written by the pattern scan)"*"**Security — credential in code**"* ]]; then
  ok "a credential added in a pull request shows in the rendered draft as a scan comment"
else
  fail "a credential added in a pull request shows in the rendered draft as a scan comment"
  printf '%s\n' "$rendered"
fi

rm -rf "$WORK"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
