# Issue Schema

The single source of truth for how issues are labeled and written across all my
repos. The issue agents (`issue-strategist`, `issue-scribe`, `issue-portfolio`)
and the bootstrap script (`claude/bin/issue-bootstrap.sh`) all read this file.
`next-task` is the executor that drains the backlog these rules produce.

## The loop

```
Portfolio  → which repo / which issue first, by leverage
  Strategist → what issues should exist in this repo
    Plan Scribe → one large request → a plan whose units are already issues
    Scribe   → write one issue, standalone
      next-task → drain the backlog into whatever each type calls for
```

A request too large to be one issue goes through the Plan Scribe first: it
writes a feature plan per `~/.claude/rules/feature-plan.md`, and that plan's
units are `type:task` bodies the breakdown files verbatim.

## What sits at each level

A **plan** is a group of features. An **issue** is a unit of work: which of
those features get built together in one pass. So an issue is not "one feature"
and it is not "a slice of a feature" — it is the batch someone picks up, works,
and opens one PR for.

That is why a task issue names its feature group in `Part of` and lists the
features it covers as acceptance criteria. The group says which plan the work
belongs to; the criteria say how much of it this pass takes.

## Label axes

Four orthogonal axes. Every issue gets exactly one `type:` and one `priority:`.

| Axis | Labels | Rule |
|---|---|---|
| **type** | `type:request` `type:plan` `type:breakdown` `type:task` `type:bug` `type:chore` `type:spike` | exactly one |
| **priority** | `priority:high` `priority:medium` `priority:low` | exactly one |
| **size** | `size:s` `size:m` `size:l` | optional |
| **status** | `blocked` `needs-grooming` | optional |
| **area** | `area:*`, freeform per repo | required on `type:task` |

`area:*` labels are freeform per repo (e.g. `area:ci`, `area:api`) for batching.
They also define the **series** `next-task` walks: issues sharing an `area:*` are one
list, drained fully before it moves on.

**Every `type:task` carries an `area:`.** It is the only routing an issue gives
`next-task`, now that no issue names a file — the label says which part of the
product the work belongs to, and the executor finds the code from there. Reuse
an existing `area:*` label rather than coining a second spelling for the same
thing; a task that genuinely fits none of them gets a new one, not none.

`next-task` stays within the current `area:*` series (inferred from the most recently
closed issue) before moving to the next series, and skips `blocked`. Within a series
it takes the highest-scoring issue by

```
score = priority_weight × (transitive_dependents + 1)
```

where `priority_weight` is high 3 / medium 2 / low 1 (missing counts as 1) and
`transitive_dependents` comes from `Blocked by #N` chains. Ties break oldest first.
`type:` is deliberately **not** in the score — it decides the deliverable, not the
value. Leverage orders a series; it never pulls the walk out of one. Keep that
contract.

## Types drive definition-of-done

| Type | Output / DoD |
|---|---|
| `type:request` | A recorded request. **No deliverable yet** — it exists to be captured; a `plan` may be spun from it later. |
| `type:plan` | **The plan is written in the issue itself** (not a committed doc) and describes a group of features. For a feature build it follows `~/.claude/rules/feature-plan.md` and `plan-scribe` writes it. A `breakdown` then divides it into units of work. **No production code.** |
| `type:breakdown` | N standalone `type:task` issues, prioritized + dependency-wired + linked back. Each is a unit of work, not necessarily one feature. |
| `type:task` | Code + tests + PR. The unit of work `next-task` executes. |
| `type:bug` | Fix + regression test + PR. |
| `type:chore` | Maintenance (deps, CI, lint). |
| `type:spike` | Time-boxed research; output is findings that feed a `plan`. |

Natural pipeline: `request → plan → breakdown → task → (next-task) → PR`.
(`spike` feeds a `plan` when research is needed first.)

**Plans live in issues, never in committed docs.** A `type:plan` issue *contains*
the plan in its body; working it produces a `type:breakdown`, not a `.md` file.

## The standalone rule (ironclad)

**No issue may reference prior context.** No "as discussed", no "continue from
#N", no "see the chat". If context is needed, it is **inlined** into the issue.
The only allowed cross-reference is a hard dependency: `Blocked by #N` (or
cross-repo `Blocked by owner/repo#N`).

This is why the Scribe is context-free: with no other context, it structurally
cannot leak one.

## The what-not-how rule (ironclad)

**An issue names what someone can do, never how or where it is built.** No file
paths, no directory names, no class or method names, no design, no plan.

Standalone means the *request* stands alone, not that the implementation is
written out in the body. A plan inlined into an issue is a snapshot of a
codebase that keeps moving, and by the time the issue is executed it is a
description of a repo that no longer exists — which is worse than no
description, because it is read as fact.

The executor reads the code. That is the source of truth for how and where, and
it is never out of date. So if something can be found by reading the repo, it
does not belong in the issue. What cannot be found by reading the repo is the
request itself: who wants what, and why. That is the whole job of the issue.

### The one exception: How it fits

A `type:task` issue sliced out of a feature plan carries one section that names
structure — `How it fits`. It holds the records that unit touches, the
relationships between them, and one line saying what the unit builds on and what
waits on it. Nothing else is exempt.

It is there because a unit arrives with its end goal missing. The plan holds the
shape of the whole feature, the issue holds one tenth of it, and the executor
never sees the two together — which is how a ten-issue feature drifts by the
third issue. This section is that tenth, and it is the smallest thing that keeps
the unit pointed at the feature.

It names records and relationships, never files, directories, classes, or
methods. That line is where the staleness is: a record is the shape of the
request and changes when the request does, while a path is only true the week the
plan was written. The executor still reads the code for how and where.

An issue with no plan behind it has nothing to put here and the section says
`Not relevant.` Never reconstruct one to fill it in — a diagram guessed from
outside the plan is exactly the stale design the rule above exists to keep out.

## Always use the Scribe (ironclad)

**Every issue is written by `issue-scribe`, in every session and every repo.**
Never write an issue body inline and never create one directly with `gh issue
create`. One Scribe per issue; it creates the issue and returns the URL.

This holds even when a session carries a general "don't spawn agents unless
asked" instruction — this rule *is* the standing request, so it satisfies that
instruction rather than conflicting with it. No exception for "the issue is
short", "the context is already gathered", or "it would be one tool call".

The one carve-out is a `type:plan` issue for a feature build: `plan-scribe`
writes and files that one itself. It is still a Scribe and still context-free —
the difference is that a plan is derived from the repo rather than handed over
as a spec, so there is nothing to pass on to a second Scribe.

Your job before spawning is the request: decide what the issue should ask for,
then hand the Scribe the intent, the repo, and the labels. The Scribe cannot
see the conversation, so anything about the *request* you leave out is gone —
but do not hand it a plan, a file list, or a design. Those are the things that
go stale, and the what-not-how rule above means the Scribe drops them anyway.

## The version stamp

Every issue body ends with a stamp naming the versions that wrote it, below the
last template section, under a `---` rule:

```
---
## Generation Metadata

Scribe: issue-scribe `0d8c9c5`
Rules: issue-schema `627b554`, writing-style `0426b47`
Model: `claude-opus-5`, cc `2.1.246`
```

It exists so an issue that came out wrong can be traced to the rules that
produced it. Reading two issues with different stamps, the commits named are
what changed between them.

The stamp is **generated, not written**: `~/.claude/bin/scribe-stamp.sh issue
"<model-id>"` prints it and the Scribe pastes it verbatim. Never type a version
by hand and never carry one over from another issue. A `+` after a commit
means that file had uncommitted edits when the issue was written, so the named
commit is not exactly what ran.

The model is named by its id, never its display name — `claude-opus-5[1m]`, not
`Opus 5 (1M context)`. A stamp is only worth reading if every scribe spells the
same model the same way, so the script refuses a display name outright.

It is a trailer, not a section. Its `## Generation Metadata` heading comes from
the script like the rest of it, so it is never listed in a template, never
written by hand, and it is not a section any type's definition-of-done reaches.

## Templates

### type:task

Open with a one-line user-story header so the purpose is clear at a glance.
Then the body.

```
**As a** <role>,
**I want** <capability>,
**so that** <value/outcome>.

## Part of
<the feature group this is a unit of work in, one sentence, and the stage it sits
in when it came from a plan — or "standalone">

## How it fits
<a mermaid diagram of only the records this unit touches, marking which are new,
or "Not relevant.">

<one sentence: what this builds on, and what waits on it>

## Acceptance criteria
- [ ] <one user-observable behavior>
- [ ] <one user-observable behavior>

## Out of scope
- <one sentence: the thing, and where it lives instead>

## Dependencies
<Blocked by #N, or "none">
```

**Part of** names the feature group this issue is a unit of work in, in the
words a person would use — "quote-to-order conversion", not a label slug. It is
a sentence, never an issue number, since the standalone rule allows no
cross-reference but `Blocked by #N`. An issue that belongs to no group says
`standalone`.

An issue sliced out of a feature plan also names the stage it sits in —
`stage 2 of 4 — Enrich`. The stage says what this unit is for: one on the thin
path that has to work before anything else does, a feature added to something
already running, duplication being paid back, or a failure being made loud. A
unit that does not know which of those it is gets built as though it were all
four.

**How it fits** is the unit's slice of the feature plan it came from — the
records it touches and nothing else, plus the one sentence placing it in the
build order. It is sliced out of the plan's own model diagram, never redrawn,
and it is the one place an issue names structure. A unit with no plan behind it
says `Not relevant.` See the exception in the what-not-how rule above.

**Acceptance criteria** are the features this unit of work covers, each stated
as a behavior observable from outside the code: what a user, a caller, or an
operator can now do. "A rep can convert a quote to an
order from the quote detail page" is one. "Add a ConvertToOrder service object"
is not — that is a plan, and plans go stale.

### type:request

```
## Request
<the raw request, in your words — capture it, don't polish it>

## Why / what it could enable
<a sentence or two, optional>

## Next
Spin a `type:plan` from this when ready (or close if dropped).
```

### type:plan

The plan IS the issue body. No committed doc.

**A plan for a feature build follows `~/.claude/rules/feature-plan.md` instead of
the template below, and `plan-scribe` writes it.** That is any request large
enough to become several issues: ten numbered sections, a model diagram, the
costs, the open decisions, and the units of work already written as `type:task`
bodies. The template here is for the smaller plan — a question to settle that
produces no feature.

Cover the design directly here:

```
## Goal
<the question to answer>

## The plan
<the actual design: options · tradeoffs · recommendation · risks — written out here>

## Done when
- [ ] Plan reviewed/approved
- [ ] A `type:breakdown` slices it into standalone tasks
- [ ] Produces NO production code

## Dependencies
<Blocked by #N, or "none">
```

### type:breakdown

```
## Source plan
<link to the plan doc/issue>

## Deliverable
N standalone `type:task` issues, each self-contained, prioritized, dependencies
wired, linked back to this issue.

## Done when
- [ ] Issues created and linked here
- [ ] This issue closed

## Dependencies
<Blocked by #N, or "none">
```
