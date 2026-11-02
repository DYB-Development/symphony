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

- **Orders may need approval** — A client could require it. That is a redesign.

---
## Generation Metadata

Scribe: plan-scribe `abc1234`
PLAN

fields() { "$SCRIPT" "$BODY" }

echo "plan-fields.sh:"

assert_equals $'Quotes become orders.\n\nNothing else changes.' "$(fields | jq -r .summary)" "reads section 01's paragraphs as the summary"

assert_equals "A quote is a source and the order is the product." "$(fields | jq -r .rule)" "reads section 01's bold line as the rule"

echo ""
echo "$PASS passed, $FAIL failed"
rm -rf "$WORK"
[[ $FAIL -eq 0 ]]
