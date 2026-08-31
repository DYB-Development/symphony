# Feature Plan

What a large feature request becomes before any code is written. It says what is
already built, what gets added, how the two fit together, what it costs, what is
still open, and the ordered units of work — each unit already in the shape of a
`type:task` issue.

It exists because a request big enough to need ten issues loses its end goal by
the third one. Issues are standalone by design, so no issue carries the whole
shape and the backlog never holds it either. The plan is the one place that
does, and each issue carries the slice of it that its own unit needs.

## Where it lives

The plan is the body of a `type:plan` issue. That issue is the source. The
published artifact is rendered from that body and from nothing else, so the two
say the same thing word for word — when the plan changes, the issue is edited
and the artifact is republished from it in the same step. The artifact is never
edited on its own.

Never a committed `.md`. A plan describes a codebase that keeps moving, and a
committed one is read as fact long after it stopped being true. The issue is
closed when its `type:breakdown` has sliced it, and what survives is the issues.

## Who writes it

`plan-scribe`, in every repo and every session. Never inline, never a second
agent, one Scribe per plan. It reads the repo itself, writes the issue, publishes
the artifact, and returns both URLs.

This holds even when a session carries a general "don't spawn agents unless
asked" instruction — this rule *is* the standing request, so it satisfies that
instruction rather than conflicting with it.

The reason is the same one behind the other Scribes, and it is sharper here.
Sections 02 and 04 are claims about what the repo already contains. A session
that has been discussing the feature for an hour will write those from what it
believes, and a plan whose "already built" section is wrong is worse than no plan
— every unit downstream is sized against it. A context-free Scribe has to go
read.

## What it is not

- **Not code.** A plan changes nothing. Its status line says so.
- **Not a breakdown.** It contains the units; a `type:breakdown` issue turns
  them into issues. Two steps, so the units get reviewed before they are filed.
- **Not a survey of the repo.** Section 02 names what this feature builds on,
  never everything that exists.
- **Not a substitute for the task issue.** Each unit still becomes a standalone
  issue, and the plan is not referenced from it.

## The header

Above section 01, four facts and nothing else:

```
Scope    <repo> · <branch the plan is written against>
Shape    <N> units in four stages
Status   proposal — no code changed
Date     <the date it was written>
```

## Which checks a plan is written to pass

Two of the checks in `~/.claude/rules/review-checks.md` apply when a feature is
planned rather than when a diff is read, because both are about a shape that is
expensive to change once it exists:

- **Design** — answered in section 04, under the model diagram.
- **Dependencies** — answered in section 07, one entry each.

**The Tests check does not apply to a plan.** A plan has no tests to look at, and
a plan that reasons about them is describing code nobody has written. The other
checks belong to a review or an audit, where there is code to point at.

## The ten sections

Always all ten, always in this order, always numbered `01`–`10` with the short
label given here. A section with nothing real to say still appears and its whole
content is the line `Not relevant.`

### 01 The plan

The whole thing in three short paragraphs, ending with **the rule everything
follows from** — one sentence, set apart, that every later section is a
consequence of. "Supplier data is a source; the team's own item is the product"
is one. If you cannot write that sentence, the plan is not ready to be written.

### 02 Already built

What the current implementation gives this feature, as short named pairs — a
name and one or two sentences. This is read out of the repo, never assumed, and
every entry is something the plan builds on rather than rewrites. It is what
keeps the plan small, and it is the section a reviewer checks hardest, so a
wrong entry here is the most expensive mistake in the document.

### 03 To be added

Every new record, every new field on an existing record, and every new piece of
machinery, as named pairs the same shape as 02. Count them in the opening line.
Name a new field on an existing record as `Existing — what the field is`, so the
additions to built things are visible at a glance.

### 04 How it fits

The section a human reads first, and the reason the plan is worth writing.

Two parts:

- **The model diagram.** Every record from 02 and 03 in one picture, with the
  relationships between them labelled in words a person would say — "one per
  team", "quotes", "varies into". New records are marked as new, new fields on
  existing records are marked with `+`, and the diagram is split so the new half
  and the existing half are visibly separate. Under it, one short paragraph
  naming **the join between the two halves** — the single place new work touches
  built work. If there is more than one join, say so; that is the most important
  fact in the plan.

  That paragraph is also where the plan answers the **Design** check from
  `~/.claude/rules/review-checks.md`: name the coupling this shape introduces,
  and the change it will make harder later. A join is coupling that has been
  chosen deliberately, and saying so before any code exists is the only point at
  which it is cheap to refuse.
- **Where the files go.** A table of model or piece, path, and state — `New`,
  `Built — unchanged`, or `Built — <what is added>`. Paths are real and relative
  to the repo's source root. This is the one place in the whole system that names
  a file, and it stays out of every issue for exactly the reason the what-not-how
  rule gives.

### 05 How it runs

A flow diagram of the paths the feature adds, then one named paragraph per path.
Say which direction data moves on each, and which paths deliberately do not read
each other. Behaviour, not call stacks.

### 06 What we gain

Why to build it. One entry per capability: the role who gets it, one sentence for
what they can now do, and the unit number from section 09 that delivers it. Every
unit in 09 should appear here at least once — a unit no capability names is a unit
worth questioning.

### 07 What we trade

What this costs. One entry per cost: a name, one or two sentences, and a short
note saying whether it is permanent, one-off, or settled by section 08. Include
the costs that come from the chosen boundary, not only the things given up.
`Not relevant.` is almost never honest here.

**Every dependency the plan takes gets its own entry**, answering the
**Dependencies** check from `~/.claude/rules/review-checks.md`: what it is, what
it does that nothing already here does, and what taking it costs. A dependency
with no entry is one nobody weighed, and the plan is the last moment weighing it
is free.

### 08 Settle first

What must be answered before the work starts, in two parts:

- **The open decisions.** Each is a question with the real options and a
  recommendation, written so I can settle it by picking one. Most plans have one;
  a plan with five open decisions is not a plan yet.
- **Answers that change the design.** Questions for someone outside the repo — a
  vendor, an API's documentation, another team. Each names the unit it would
  change and why it is a redesign rather than a bug fix if it comes back wrong.

### 09 The work

The units, in four stages. Each unit is one pass and one pull request, and each
is written as a complete `type:task` issue body per `~/.claude/rules/issue-schema.md`
— user-story header, `Part of`, `How it fits`, acceptance criteria, out of scope,
dependencies. They are copied into issues verbatim, so a unit written loosely
here is a loose issue later.

**The stages, always these four and always in this order:**

**1 · End to end** — the thinnest path that works front to back and can be
demonstrated. A notification is created and then sent; nothing else. Only units
on that path belong here, and a unit that is not on it goes in a later stage
however small it is. If stage one cannot be demonstrated, it is not stage one.

**2 · Enrich** — the features the thin path does not have yet. The receiver's
communication preferences, a second channel to send on. Each is added to
something that already runs.

**3 · Simplify** — the same behaviour with less of it. What was written twice
while the shape was still moving gets written once, now that the shape is known.
This stage is where duplication earned during stages one and two is paid back,
and it changes no behaviour.

**4 · Harden** — what fails quietly today. Errors, retries, limits, and the
checks that catch a mistake in the same session it was made.

**Every stage says how its work is turned off or rolled back**, in one sentence
under the stage heading. A stage nobody can back out of is a stage that ships
whether it is right or not.

**The Harden stage also says how a failure in production is noticed.** Code that
breaks silently is not hardened, however carefully it handles errors.

**Units are numbered `<stage>.<n>`** — `Unit 1.1`, `Unit 2.3` — so a number says
which stage a unit is in and where it sits inside it. A dependency names exactly
one unit by that number (`Blocked by Unit 1.3`); they become issue numbers when
the issues are filed.

Ten units is a large plan. Past about twelve, the request is two features. A
stage may hold one unit, and a small feature whose stages hold one unit each is
telling you it did not need a plan.

### 10 Risks

What could still change the shape of the plan — not what could go wrong while
building it. Each is one bold claim and one or two sentences, and each is
something that would be a redesign rather than a fix. Missing infrastructure
belongs here. So does anything section 08 asked about whose answer could come
back badly.

## Diagrams

Sections 04 and 05 carry the diagrams, and they are the reason the plan gets
read. Rules:

- **Authored once, as mermaid.** GitHub renders mermaid in an issue body and
  artifacts render it natively, so the same fenced block serves both and the two
  cannot drift. Do not hand-draw one version and mermaid the other.
- **Label every edge in words.** An unlabelled line between two boxes tells a
  reviewer nothing, and verifying the relationships is the whole job of section
  04.
- **Mark state on the node.** New, built, and built-with-a-new-field are three
  different things and the picture has to show which is which.
- **One picture per section.** If section 04 needs two diagrams, the plan is
  describing two features.

## One sentence means one sentence

The rule from `~/.claude/rules/pr-body.md` applies to every bullet, every named
pair's body, and every acceptance criterion here. One sentence, one period, no
semicolon, no clause bolted on the end. A named pair may run to two sentences
where the second states a consequence; nothing runs to three.

The prose paragraphs in 01, 04, and 05 are the exception — they are paragraphs,
and they are still short.

And `~/.claude/rules/writing-style.md` applies to every word. No metaphors, no
narration of the work, no filler.

## The version stamp

Every plan ends with a stamp naming the versions that wrote it, below section 10,
under a `---` rule:

```
---
## Generation Metadata

Scribe: plan-scribe `4e655ad`
Rules: feature-plan `4e655ad`, writing-style `0426b47`
Model: `claude-opus-5`, cc `2.1.246`

Planned Against: `acme/quotes@a1b2c3d`
```

It is **generated, not written**: `~/.claude/bin/scribe-stamp.sh plan
"<model-id>"` prints it and the Scribe pastes it verbatim. Never type a version
by hand. A `+` after a commit means that file had uncommitted edits when the plan
was written. The model is named by its id, never its display name.

`Planned Against` is the repo and commit the plan was written against, read from
the working directory the Scribe ran in, and it sits below the rest after a
blank line. It is there because sections 02 and 04 are
claims about what the repo contained at one moment, and a plan read six weeks
later is only checkable against the commit it describes. A `+` there means the
tree was dirty, so the commit named is not exactly what was read.

It is a trailer, not an eleventh section.
