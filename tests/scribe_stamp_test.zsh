#!/usr/bin/env zsh
# Tests for bin/scribe-stamp.sh. Every case runs against a throwaway
# rules root so this repo's own history is never read.
#
# Usage: zsh zsh/scribe_stamp_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
STAMP="$SCRIPT_DIR/../bin/scribe-stamp.sh"

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

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
    printf '      in:             %s\n' "${(qqq)haystack}"
  fi
}

new_root() {
  SCRIBE_STAMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scribe_stamp_test.XXXXXX")"
  export SCRIBE_STAMP_ROOT
  git -C "$SCRIBE_STAMP_ROOT" init -q
  mkdir -p "$SCRIBE_STAMP_ROOT/agents" "$SCRIBE_STAMP_ROOT/rules"
}

commit_rules() {
  local file
  for file in "$@"; do
    printf 'contents\n' > "$SCRIBE_STAMP_ROOT/$file"
    git -C "$SCRIBE_STAMP_ROOT" add "$file"
    git -C "$SCRIBE_STAMP_ROOT" commit -qm "add $file"
  done
}

sha_of() {
  git -C "$SCRIBE_STAMP_ROOT" log -1 --format=%h -- "$1"
}

drop_root() {
  rm -rf "$SCRIBE_STAMP_ROOT"
  unset SCRIBE_STAMP_ROOT
}

new_source() {
  SOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scribe_stamp_source.XXXXXX")"
  git -C "$SOURCE_DIR" init -q
  git -C "$SOURCE_DIR" remote add origin git@github.com:acme/quotes.git
  printf 'code\n' > "$SOURCE_DIR/app.rb"
  git -C "$SOURCE_DIR" add app.rb
  git -C "$SOURCE_DIR" commit -qm "add app"
}

source_head() {
  git -C "$SOURCE_DIR" rev-parse --short HEAD
}

drop_source() {
  rm -rf "$SOURCE_DIR"
  unset SOURCE_DIR
}

echo "scribe-stamp.sh pr:"

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
assert_equals "## Generation Metadata

Scribe: pr-scribe \`$(sha_of agents/pr-scribe.md)\`" \
  "$("$STAMP" pr claude-opus-5 | sed -n '1,3p')" \
  "heads the stamp with the section naming the versions"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
assert_equals "Scribe: pr-scribe \`$(sha_of agents/pr-scribe.md)\`" \
  "$("$STAMP" pr claude-opus-5 | sed -n 3p)" \
  "names the scribe and the commit that last touched its prompt"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
assert_equals "Rules: pr-body \`$(sha_of rules/pr-body.md)\`, writing-style \`$(sha_of rules/writing-style.md)\`" \
  "$("$STAMP" pr claude-opus-5 | sed -n 4p)" \
  "names each rules file the pr scribe follows and its own commit"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
assert_equals "Model: \`claude-opus-5\`, cc \`9.9.9\`" \
  "$(AI_AGENT=claude-code_9-9-9_agent "$STAMP" pr claude-opus-5 | sed -n 5p)" \
  "names the model that wrote the body and the cli it ran under"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
assert_equals "Model: \`claude-opus-5\`, cc \`unknown\`" \
  "$(AI_AGENT= PATH=/usr/bin:/bin "$STAMP" pr claude-opus-5 | sed -n 5p)" \
  "names the cli unknown when there is none to ask for a version"
drop_root

echo ""
echo "scribe-stamp.sh issue:"

new_root
commit_rules agents/issue-scribe.md rules/issue-schema.md rules/writing-style.md
assert_equals "Scribe: issue-scribe \`$(sha_of agents/issue-scribe.md)\`
Rules: issue-schema \`$(sha_of rules/issue-schema.md)\`, writing-style \`$(sha_of rules/writing-style.md)\`" \
  "$("$STAMP" issue claude-opus-5 | sed -n '3,4p')" \
  "names the issue scribe and the schema it followed"
drop_root

echo ""
echo "scribe-stamp.sh plan:"

new_root
commit_rules agents/plan-scribe.md rules/feature-plan.md rules/review-checks.md rules/writing-style.md
assert_equals "Scribe: plan-scribe \`$(sha_of agents/plan-scribe.md)\`
Rules: feature-plan \`$(sha_of rules/feature-plan.md)\`, review-checks \`$(sha_of rules/review-checks.md)\`, writing-style \`$(sha_of rules/writing-style.md)\`" \
  "$("$STAMP" plan claude-opus-5 | sed -n '3,4p')" \
  "names the plan scribe, the feature plan schema and the checks it was written to pass"
drop_root

new_root
new_source
commit_rules agents/plan-scribe.md rules/feature-plan.md rules/review-checks.md rules/writing-style.md
assert_equals "
Planned Against: \`acme/quotes@$(source_head)\`" \
  "$(cd "$SOURCE_DIR" && "$STAMP" plan claude-opus-5 | sed -n '6,7p')" \
  "names the repo and commit the plan was written against, below the rest"
drop_source
drop_root

echo ""
echo "scribe-stamp.sh review:"

new_root
commit_rules agents/review-scribe.md rules/review-checks.md rules/pr-review.md rules/writing-style.md
assert_equals "Scribe: review-scribe \`$(sha_of agents/review-scribe.md)\`
Rules: review-checks \`$(sha_of rules/review-checks.md)\`, pr-review \`$(sha_of rules/pr-review.md)\`, writing-style \`$(sha_of rules/writing-style.md)\`" \
  "$("$STAMP" review claude-opus-5 | sed -n '3,4p')" \
  "names the review scribe, the checks it ran and the review rules it followed"
drop_root

new_root
new_source
commit_rules agents/review-scribe.md rules/review-checks.md rules/pr-review.md rules/writing-style.md
assert_equals "
Reviewed Against: \`acme/quotes@deadbee\`" \
  "$(cd "$SOURCE_DIR" && "$STAMP" review claude-opus-5 acme/quotes@deadbee | sed -n '6,7p')" \
  "names the head commit a review was given instead of the one it ran from"
drop_source
drop_root

echo ""
echo "scribe-stamp.sh audit:"

new_root
commit_rules agents/audit-scribe.md rules/repo-audit.md rules/review-checks.md rules/audit-rubric.json rules/writing-style.md
assert_equals "Scribe: audit-scribe \`$(sha_of agents/audit-scribe.md)\`
Rules: repo-audit \`$(sha_of rules/repo-audit.md)\`, review-checks \`$(sha_of rules/review-checks.md)\`, audit-rubric \`$(sha_of rules/audit-rubric.json)\`, writing-style \`$(sha_of rules/writing-style.md)\`" \
  "$("$STAMP" audit claude-opus-5 | sed -n '3,4p')" \
  "names the audit scribe, the audit rules, the checks and the rubric that scored it"
drop_root

new_root
new_source
commit_rules agents/audit-scribe.md rules/repo-audit.md rules/review-checks.md rules/audit-rubric.json rules/writing-style.md
assert_equals "
Audited Against: \`acme/quotes@$(source_head)\`" \
  "$(cd "$SOURCE_DIR" && "$STAMP" audit claude-opus-5 | sed -n '6,7p')" \
  "names the repo and commit an audit read, below the rest"
drop_source
drop_root

new_root
new_source
commit_rules agents/audit-scribe.md rules/repo-audit.md rules/review-checks.md rules/audit-rubric.json rules/writing-style.md
printf 'edited\n' > "$SOURCE_DIR/app.rb"
assert_equals "Audited Against: \`acme/quotes@$(source_head)+\`" \
  "$(cd "$SOURCE_DIR" && "$STAMP" audit claude-opus-5 | sed -n 7p)" \
  "marks an audit of a tree that had uncommitted changes"
drop_source
drop_root

echo ""
echo "scribe-stamp.sh uncommitted rules:"

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
printf 'edited\n' > "$SCRIBE_STAMP_ROOT/agents/pr-scribe.md"
assert_equals "Scribe: pr-scribe \`$(sha_of agents/pr-scribe.md)+\`" \
  "$("$STAMP" pr claude-opus-5 | sed -n 3p)" \
  "marks a version whose file has uncommitted edits"
drop_root

echo ""
echo "scribe-stamp.sh missing files:"

new_root
commit_rules agents/pr-scribe.md rules/writing-style.md
"$STAMP" pr claude-opus-5 >/dev/null 2>&1
assert_equals "70" "$?" "fails when a rules file it names is not there"
drop_root

new_root
commit_rules rules/pr-body.md rules/writing-style.md
"$STAMP" pr claude-opus-5 >/dev/null 2>&1
assert_equals "70" "$?" "fails when the agent file it names is not there"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/writing-style.md
assert_contains \
  "rules/pr-body.md" \
  "$("$STAMP" pr claude-opus-5 2>&1)" \
  "names the file it could not find"
drop_root

echo ""
echo "scribe-stamp.sh usage:"

new_root
"$STAMP" pr >/dev/null 2>&1
assert_equals "64" "$?" "exits with a usage code when the model is not named"
drop_root

echo ""
echo "scribe-stamp.sh source form:"

new_root
commit_rules agents/review-scribe.md rules/review-checks.md rules/pr-review.md rules/writing-style.md
"$STAMP" review claude-opus-5 deadbee >/dev/null 2>&1
assert_equals "64" "$?" "refuses a source that does not name a repo and a commit"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
"$STAMP" pr claude-opus-5 acme/quotes@deadbee >/dev/null 2>&1
assert_equals "64" "$?" "refuses a source for a scribe whose stamp carries none"
drop_root

echo ""
echo "scribe-stamp.sh model form:"

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
"$STAMP" pr "Opus 5 (1M context)" >/dev/null 2>&1
assert_equals "64" "$?" "refuses a model given as a display name instead of an identifier"
drop_root

new_root
commit_rules agents/pr-scribe.md rules/pr-body.md rules/writing-style.md
assert_equals "Model: \`claude-opus-5[1m]\`, cc \`9.9.9\`" \
  "$(AI_AGENT=claude-code_9-9-9_agent "$STAMP" pr 'claude-opus-5[1m]' | sed -n 5p)" \
  "accepts an identifier carrying a context marker"
drop_root

echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
