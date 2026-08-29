# PR Body Template

A PR body is short. Every section below is always present, in this order — a
section with nothing real to say carries `Not relevant.` and nothing else. No
narration of the work, no test counts, no design essay. CI proves the tests; the
diff proves the code. The body exists so a reviewer knows what to look for.

```
## One Sentence Summary

<One sentence a non-programmer can follow: a specific user, and what they can
now do or no longer have to deal with.>

## ACs Covered

- [x] <one sentence>
- [x] <one sentence>

## Decision Log

### <the question that was open, as a question>

> <one sentence: the choice made, and the option it was made over>

## Code Example

```<lang>
<how a caller uses the surface this PR adds>
```

## Out of Scope

- <one sentence: the thing, and where it actually lives>

## Ticket Billed Against

- <the ticket this work is billed against>
```

All six sections appear in every body, always in that order. Nothing else,
apart from the two trailers below.
Never add a section that is not on this list, and never drop one — when Design
Decisions, Code Example, or Out of Scope has nothing to say, the section stays
and its whole content is the line `Not relevant.` Ticket Billed Against says
`Not specified.` instead, since a missing ticket is a fact about the billing and
not an empty section. One Sentence Summary and ACs Covered always have something
to say.

## Always use the PR Scribe (ironclad)

**Every PR body, in every repo, is written by `pr-scribe`.** Never write one
inline and never pass a body to `gh pr create` yourself. One Scribe per PR; it
opens or updates the PR and returns the URL.

This holds even when a session carries a general "don't spawn agents unless
asked" instruction — this rule *is* the standing request, so it satisfies that
instruction rather than conflicting with it. No exception for "the PR is small",
"it's a one-line fix", or "I already know what it changed".

That last one is the reason for the rule. A session that did the work remembers
doing it, and writes the body from that memory — which is exactly how a PR body
turns into narration, inherits a stale claim from the issue, or ticks an
acceptance criterion the diff does not actually cover. The Scribe cannot do
that: with no memory of the work, it has to go read `git diff main...HEAD` and
the issue, so what it writes is what actually landed.

Your job before spawning is the pointer, not the prose: hand it the repo, the
branch, and the issue number (or the acceptance criteria inlined if there is no
issue). It reads the rest from the repo.

## The `Closes #N` trailer

A PR that resolves an issue ends with `Closes #<n>` on its own line after the
last section. That trailer is machine-readable wiring, not a seventh section — it
is one of the two things allowed outside the six.

## The version stamp

The other. Every body ends with a stamp naming the versions that wrote it,
below `Closes #N`, under a `---` rule:

```
Closes #42

---
## Generation Metadata

Scribe: pr-scribe `4e655ad`
Rules: pr-body `4e655ad`, writing-style `0426b47`
Model: `claude-opus-5`, cc `2.1.246`
```

It exists so a body that came out wrong can be traced to the rules that
produced it. Reading two bodies with different stamps, the commits named are
what changed between them.

The stamp is **generated, not written**: `~/.claude/bin/scribe-stamp.sh pr
"<model-id>"` prints it and the Scribe pastes it verbatim. Never type a version
by hand and never carry one over from another body. A `+` after a commit
means that file had uncommitted edits when the body was written, so the named
commit is not exactly what ran.

The model is named by its id, never its display name — `claude-opus-5[1m]`, not
`Opus 5 (1M context)`. A stamp is only worth reading if every scribe spells the
same model the same way, so the script refuses a display name outright.

It is a trailer, not a section. Its `## Generation Metadata` heading comes from
the script like the rest of it, so it is never counted among the six, never
written by hand, and the one-sentence rule does not reach it.

## One sentence means one sentence

This is the rule the body lives or dies by, and it governs every line above.

- One sentence. One period. No semicolons, no em-dash clause bolted on the end,
  no "so that", no parenthetical aside explaining the mechanism.
- No code, no identifiers, no file paths, no output, no nested block inside a
  bullet. If a claim needs a snippet to be believed, the snippet belongs in the
  diff, not in the body.
- No bold labels inside a bullet. No sub-bullets. Decision Log is the one
  section built from question headings instead of bullets, and its heading is
  the question itself, never a label bolted onto an answer.
- If it will not fit, the bullet is carrying two claims — split it into two
  bullets, or cut the half a reviewer will not check.

Rule of thumb: a bullet longer than about twenty words is not a bullet.

## Section rules

**One Sentence Summary** — write it for someone who does not read code. Name the
user — a role in the app (a rep, an admin), or a developer, or the person
running deploys — and say what they can now do, or what they no longer have to
deal with. "A rep can build a quote line item up from its parts" beats "adds
nested line item support to the transaction editor." Never a list of files
touched, never the word "refactor".

**ACs Covered** — one testable claim per bullet, one sentence each. If the
ticket has acceptance criteria, these *are* those criteria, one bullet apiece.
If it does not, write what is now true that was not before. A bug fix is an AC:
state the behaviour that now holds, not the story of finding it. Do not tick an
AC the diff does not cover — leave it unticked and say so in one sentence.
Never explain *how* a bullet was implemented; the reviewer reads the diff for
that.

**Decision Log** — a history, not a summary of the current state. Entries are
chronological and an earlier one may have been superseded by a later one; the
diff is what is true now. Pairs, not bullets: a heading holding the question
that was open, and one sentence blockquoted under it holding the answer, so a
reader sees at a glance where the question ends and the decision begins. The
question is what makes it a decision rather than an assertion, so it is never
dropped — an answer standing alone leaves the reviewer unable to see what was
at stake.
This section is **generated, not written**: `~/.claude/bin/decide.sh --render`
prints it from the branch's `.decisions.md`, and the Scribe pastes that output
verbatim. Nobody rewords a question or tightens an answer after the fact,
because the session that made the choice wrote the entry and every later edit
trades a fact for a guess. The only permitted change is deleting an entry the
diff flatly contradicts, whole. With no log there is nothing to render, and
only then are the choices reconstructed from the diff — a fallback, not the
path. A pair earns its place only when someone could reasonably have gone the
other way: the storage picked over another, the boundary the logic was put behind,
a dependency taken or refused, an existing pattern deliberately broken. Name
the choice and the option it was made over and stop there. This is not the place to
defend the choice at length, re-argue it, or explain how it was built; if a
reviewer needs the full argument, that is a comment on the diff. A PR that
only did the obvious thing has nothing to log, and the section says `Not
relevant.`

**Code Example** — only when the PR exposes a call surface or a DSL someone will
write against: a new util, composable, harness, script or endpoint. Take the
snippet from the real code, never compose one from memory. For UI, workflow and
internal refactor changes, and for a surface with exactly one caller added in
the same PR, the section says `Not relevant.` When in doubt, `Not relevant.`

**Out of Scope** — bullets, one sentence each. Each names one thing a reader
will reasonably expect to find here and will not, plus where it actually lives —
the ticket, PR or discussion that owns it. Most PRs have nothing to put here and
the section says `Not relevant.` Never use it to justify a decision, explain a
design, or write up why something was skipped; a decision worth naming goes in
Decision Log as one sentence, and reasoning a reviewer must weigh is a
comment on the diff.

**Ticket Billed Against** — the client ticket or tickets this branch's hours are
billed to, one bullet each. This section is **generated, not written**:
`~/.claude/bin/ticket.sh --render` prints it from the branch's `.ticket` file
and the Scribe pastes that output verbatim. With nothing recorded it prints
`Not specified.`, which is the honest answer for internal work and for a branch
whose ticket has not been named yet. A ticket found later is recorded with
`~/.claude/bin/ticket.sh "<reference>"` and picked up the next time the Scribe
updates the body, so the section is never edited by hand. A branch may carry
more than one ticket, and one ticket may span several branches.

## What does not go in a PR body

- Test counts, suite names, pass/fail tallies — CI reports these.
- A "what changed" list that restates the ACs in worse prose.
- The argument behind a decision. Decision Log names the choice in one
  sentence; the case for it belongs in the diff and its comments.
- Environment excuses — a local toolchain that could not run something is not
  the reviewer's problem.
- Restating the PR title or the ticket key as a heading.
- Filler like "Bespoke vs ceremony" or a wiring map. If the wiring is hard to
  follow, that is a comment on the diff, not a paragraph in the body.
