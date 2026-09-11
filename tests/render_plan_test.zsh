#!/usr/bin/env zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
RENDER="$SCRIPT_DIR/../bin/render-plan.sh"

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label"
    printf '      wanted to find: %s\n' "${(qqq)needle}"
  fi
}

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

new_issue() {
  STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/render_plan_test.XXXXXX")"
  cat > "$STUB_DIR/gh" <<'SH'
#!/usr/bin/env bash
here="$(dirname "$0")"
case "$1 $2" in
  "issue view")
    [ "${ISSUE_EXIT:-0}" = 0 ] || exit "$ISSUE_EXIT"
    cat "$here/issue.json"
    ;;
  "api markdown")
    shift 2
    while [ $# -gt 0 ]; do
      [ "$1" = -F ] && src="${2#text=@}"
      shift
    done
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "") ;;
        "##### "*) printf '<h5>%s</h5>\n' "${line#"##### "}" ;;
        "<"*) printf '%s\n' "$line" ;;
        *) printf '<p>%s</p>\n' "$line" ;;
      esac
    done < "$src"
    ;;
esac
SH
  chmod +x "$STUB_DIR/gh"
  jq -n --arg title "$1" --arg body "$(cat)" '{title: $title, body: $body}' > "$STUB_DIR/issue.json"
}

drop_issue() {
  rm -rf "$STUB_DIR"
}

render() {
  PATH="$STUB_DIR:$PATH" "$RENDER" acme/quotes 42 2>&1
}

echo "render-plan.sh:"

"$RENDER" >/dev/null 2>&1
assert_equals "64" "$?" "refuses to run without a repo and an issue number"

new_issue "Quote Conversion" <<'MD'
## 01 The plan
MD
ISSUE_EXIT=1 render >/dev/null
assert_equals "70" "$?" "exits 70 when the plan issue cannot be read"
drop_issue

new_issue "Quotes & Orders <v2>" <<'MD'
## 01 The plan
MD
assert_contains "<title>Quotes &amp; Orders &lt;v2&gt;</title>" "$(render)" \
  "names the page after the plan issue's title"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 01 The plan
MD
assert_contains "<style>$(cat "$SCRIPT_DIR/../templates/plan-page.css")</style>" "$(render)" \
  "styles every plan page with the one shipped stylesheet"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 01 The plan
MD
assert_contains '<header class="masthead"><p class="kicker">Feature plan · acme/quotes#42</p><h1>Quote Conversion</h1>' "$(render)" \
  "heads the page with the plan's issue and its name"
drop_issue

new_issue "Quote Conversion" <<'MD'
[Quote Conversion](https://claude.ai/code/artifact/abc)

```
Scope    acme/quotes · main
Shape    4 units in four stages
Status   proposal — no code changed
Date     2026-09-11
```

## 01 The plan
MD
assert_contains '<dl class="facts"><div><dt>Scope</dt><dd>acme/quotes · main</dd></div><div><dt>Shape</dt><dd>4 units in four stages</dd></div><div><dt>Status</dt><dd>proposal — no code changed</dd></div><div><dt>Date</dt><dd>2026-09-11</dd></div></dl>' "$(render)" \
  "shows the plan's four header facts under its name"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 01 The plan

Quotes become orders.

## 02 Already built

- Quotes
MD
assert_contains '<section class="part" aria-labelledby="s02"><h2 id="s02"><span class="num">02</span> Already built</h2>' "$(render)" \
  "opens each numbered section with its number and label"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 01 The plan

Quotes become orders.
MD
assert_contains '<p>Quotes become orders.</p>' "$(render)" \
  "turns each section's markdown into HTML through GitHub's markdown service"
drop_issue

new_issue "Quote Conversion" <<'MD'
[Quote Conversion](https://claude.ai/code/artifact/abc)

## 01 The plan
MD
[[ "$(render)" != *"claude.ai/code/artifact/abc"* ]]
assert_equals "0" "$?" "leaves the link to the page itself off the page"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 09 The work

### Stage 1 · End to end

A rep converts one quote.
MD
assert_contains '<section class="stage" data-stage="1"><h3 id="stage-1">Stage 1 · End to end</h3>' "$(render)" \
  "opens each stage of the work with its number and name"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 09 The work

### Stage 1 · End to end

#### Unit 1.2 — Convert a quote

**As a** rep,
MD
assert_contains '<article class="unit" data-stage="1"><h4 id="unit-1-2"><span class="unum">Unit 1.2</span> <span class="utitle">— Convert a quote</span></h4>' "$(render)" \
  "puts each unit in its own card, coloured by its stage"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 09 The work

### Stage 1 · End to end

#### Unit 1.2 — Convert a quote

## Part of
MD
assert_contains '<h5>Part of</h5>' "$(render)" \
  "sets a unit's own headings below the unit's title"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 04 How it fits

```mermaid
flowchart LR
  Quote -->|"becomes"| Order
```
MD
assert_contains '<figure class="diagram"><pre class="mermaid">flowchart LR
  Quote --&gt;|"becomes"| Order</pre></figure>' "$(render)" \
  "hands each mermaid diagram to the page as diagram source"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 10 Risks

- One risk.

---
## Generation Metadata

Scribe: plan-scribe `abc1234`
MD
assert_contains '</section><footer class="stamp"><h2 id="stamp">Generation Metadata</h2>' "$(render)" \
  "sets the version stamp apart below the last section"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 04 How it fits

<markdown-accessiblity-table><table role="table">
MD
assert_contains '<div class="table-wrap"><table role="table">' "$(render)" \
  "lets a wide table scroll inside its own box"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 01 The plan

## 09 The work

### Stage 1 · End to end

#### Unit 1.1 — Convert a quote
MD
assert_contains '<ol class="toc"><li><a href="#s01"><span class="num">01</span> The plan</a></li><li><a href="#s09"><span class="num">09</span> The work</a><ol class="toc-units"><li class="toc-stage"><a href="#stage-1">Stage 1 · End to end</a></li><li><a href="#unit-1-1"><span class="unum">1.1</span> Convert a quote</a></li></ol></li></ol>' "$(render)" \
  "lists every section, stage and unit in the contents"
drop_issue

new_issue "Quote Conversion" <<'MD'
## 01 The plan
MD
[[ "$(render)" == *"</style>"*"<div class=\"shell\">"*"</aside>"*"<main>"*"<header class=\"masthead\">"*"</main>"*"</div>" ]]
assert_equals "0" "$?" "lays out the contents beside the plan, with the plan under its masthead"
drop_issue

echo ""
echo "the plan scribe:"

PLAN_SCRIBE="$SCRIPT_DIR/../agents/plan-scribe.md"

grep -qF '~/.claude/bin/render-plan.sh' "$PLAN_SCRIBE"
assert_equals "0" "$?" "publishes the page the render script builds from the filed issue"

grep -qF 'gh issue list' "$PLAN_SCRIBE"
assert_equals "1" "$?" "does not survey the repo's open issues"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
