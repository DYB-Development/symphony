#!/usr/bin/env zsh
# Tests for bin/plan-fields.sh.
#
# Usage: zsh tests/plan_fields_test.zsh
setopt no_unset

SCRIPT_DIR="${0:A:h}"
SCRIPT="$SCRIPT_DIR/../bin/plan-fields.sh"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/plan_fields_test.XXXXXX")"
BODY="$WORK/body.md"

cat > "$BODY" <<'PLAN'
Scope    acme/shop · main
Shape    2 units in four stages
Status   proposal — no code changed
Date     2026-11-02

## 01 The plan

Quotes become orders.

Nothing else changes.

**A quote is a source and the order is the product.**

## 02 Already built

- **Quote record** — A quote holds its lines.
- **Order record** — An order holds its lines.

## 03 To be added

Two new pieces.

- **Convert action** — Turns a quote into an order.

## 04 How it fits

```mermaid
flowchart LR
  Quote --> Order
```

There is one join, at the convert action.

| Piece | Path | State | Pattern followed |
|---|---|---|---|
| Convert action | `app/models/order.rb` | New | Not relevant |

## 05 How it runs

```mermaid
flowchart TD
  Rep --> Convert
```

**Converting.** A rep converts a quote from its page.

**Reading.** An order page reads its own lines.

## 06 What we gain

- **Rep** — Can convert a quote to an order. (Unit 1.1)

## 07 What we trade

- **One more page** — The order page is new. Permanent.

## 08 Settle first

**Open decisions**

1. **Where does the convert button sit?**
   - Option one: on the quote page.
   - Option two: on the quotes list.
   - Recommendation: on the quote page.
   - Why: a rep reads the quote first.
   - **Decided:** on the quote page.

**Answers that change the design**

- **Tax rules** — Asked of the accountant.

## 09 The work

### Stage 1 · End to end

#### Unit 1.1 — Convert a quote (shop)

**As a** rep,
**I want** to convert a quote,
**so that** the order needs no retyping.

## Part of
Quote-to-order conversion, stage 1 of 4 — End to end.

## How it fits
```mermaid
flowchart LR
  Quote["Quote · built"] -- "becomes" --> Order["Order · new"]
```

This builds on quotes.

## Acceptance criteria
- [ ] A rep can convert a quote from its page.
- [ ] The order carries the quote's lines.

## Out of scope
- Partial conversion, which is a later request.

## Dependencies
none

### Stage 2 · Enrich

#### Unit 2.1 — Email the order (shop)

**As a** rep,
**I want** the order emailed,
**so that** the client sees it.

## Part of
Quote-to-order conversion, stage 2 of 4 — Enrich.

## How it fits
Not relevant.

## Acceptance criteria
- [ ] The client gets the order by email.

## Out of scope
- Not relevant.

## Dependencies
Blocked by Unit 1.1

## 10 Risks

- **Orders may need approval.** A client could require it, which is a redesign.

---
## Generation Metadata

Scribe: plan-scribe `abc1234`
PLAN

fields() { "$SCRIPT" "$BODY" }

echo "plan-fields.sh:"

assert_equals $'Quotes become orders.\n\nNothing else changes.' "$(fields | jq -r .summary)" "reads section 01's paragraphs as the summary"

assert_equals "A quote is a source and the order is the product." "$(fields | jq -r .rule)" "reads section 01's bold line as the rule"

assert_equals '[{"name":"Quote record","body":"A quote holds its lines."},{"name":"Order record","body":"An order holds its lines."}]' \
  "$(fields | jq -c .already_built)" "reads section 02's named pairs as what is already built"

assert_equals '[[{"name":"Convert action","body":"Turns a quote into an order."}],[{"name":"One more page","body":"The order page is new. Permanent."}]]' \
  "$(fields | jq -c '[.to_be_added, .trades]')" "reads the named pairs of sections 03 and 07 as what is added and traded"

assert_equals $'flowchart LR\n  Quote --> Order' "$(fields | jq -r .model_diagram)" "reads section 04's mermaid block as the model diagram"

assert_equals '[{"body":"There is one join, at the convert action."}]' "$(fields | jq -c .how_it_fits)" \
  "reads section 04's paragraphs, leaving out its diagram and file table, as how it fits"

assert_equals $'flowchart TD\n  Rep --> Convert' "$(fields | jq -r .flow_diagram)" "reads section 05's mermaid block as the flow diagram"

assert_equals '[{"name":"Converting","body":"A rep converts a quote from its page."},{"name":"Reading","body":"An order page reads its own lines."}]' \
  "$(fields | jq -c .how_it_runs)" "reads section 05's named paragraphs as how it runs"

assert_equals '[{"role":"Rep","body":"Can convert a quote to an order. (Unit 1.1)"}]' "$(fields | jq -c .gains)" \
  "reads section 06's pairs as gains led by the role"

assert_equals '[{"question":"Where does the convert button sit?","options":["on the quote page.","on the quotes list."],"recommendation":"on the quote page.","choice":"on the quote page."}]' \
  "$(fields | jq -c .decisions)" "reads section 08's open decisions with their options, recommendation and choice"

assert_equals '{"number":"1.1","stage":1,"title":"Convert a quote","user_story":"**As a** rep,\n**I want** to convert a quote,\n**so that** the order needs no retyping.","part_of":"Quote-to-order conversion, stage 1 of 4 — End to end.","how_it_fits":"flowchart LR\n  Quote[\"Quote · built\"] -- \"becomes\" --> Order[\"Order · new\"]","acceptance_criteria":["A rep can convert a quote from its page.","The order carries the quote'"'"'s lines."],"out_of_scope":["Partial conversion, which is a later request."],"waits_on":[]}' \
  "$(fields | jq -c '.units[0]')" "reads a section 09 unit's number, stage, title, story, part, diagram, criteria and out of scope"

assert_equals '["1.1"]' "$(fields | jq -c '.units[1].waits_on')" "reads the units a unit is blocked by as the units it waits on"

assert_equals '[{"name":"Orders may need approval.","body":"A client could require it, which is a redesign."}]' "$(fields | jq -c .risks)" \
  "reads section 10's bold claims and what follows them as the risks"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
