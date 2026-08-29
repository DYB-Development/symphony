---
description: Turn a large feature request into a reviewable plan — what is built, what gets added, how it fits, what it costs, and the ordered units of work
---

You are taking a feature request large enough that building it straight away
would lose its end goal by the third issue. It becomes a plan first: a
`type:plan` issue and the artifact that renders it, with the units of work
written out and ready to be filed once I have read them.

**Read `~/.claude/rules/feature-plan.md`** — the header, the ten sections, the
diagram rules, and where the plan lives are all there.

You do not write the plan. **`plan-scribe` writes it**, always — spawn it with
the **Agent tool, `subagent_type: plan-scribe`**, one Scribe per plan. It runs
context-free so it has to read the repo instead of writing section 02 from what
this session already believes.

## What you do

1. **Get the request straight before spawning.** The Scribe sees nothing but
   what you hand it, so anything about the *request* you leave out is gone. Ask
   me directly about anything genuinely ambiguous — one question, plain words —
   and do not ask about anything the repo answers.

   What it needs: the repo, the branch to plan against, what I want to be able
   to do, who does it, and anything I have already ruled out.

   What it does not need: your reading of the codebase. Do not hand it a design,
   a file list, or the models you think it should add. Those are the parts of the
   plan it is supposed to derive, and handing it yours is how a plan comes back
   confirming a guess instead of checking one.

2. **Spawn the Scribe** and wait. It reads the repo, writes the plan, files the
   issue, publishes the artifact, and returns both URLs with the open decisions.

3. **Report back**: the artifact link first, then the issue, the unit count, and
   the questions section 08 leaves open. Then stop — the plan is for me to read.

4. **When I have read it and settled section 08**, edit the answers into the
   issue body and republish the artifact from it in the same step, then file the
   `type:breakdown` that slices the units into `type:task` issues. The units are
   already written as issue bodies, so the breakdown copies them rather than
   rewriting them — hand each to an `issue-scribe` with the unit's body inlined
   and its `Blocked by` wired to the issue numbers the earlier units got.

## Rules

- **The plan changes no code.** Not a branch, not a commit, not a spike to check
  something. If a question can only be answered by writing code, it belongs in
  section 08 or as a `type:spike`.
- **Do not start the work.** Not the first unit, not the migration, not the
  small obvious piece. The plan is the deliverable.
- **Do not file the task issues yourself.** That is step 4, after I read the
  units, and it is a `type:breakdown`.
- **One plan per request.** If what I asked for is really two features, say so
  and ask which one to plan.
- **Do not summarise the plan back to me.** I am going to read it. Give me the
  links, the unit count, and the open questions.

Write to the rules in `~/.claude/rules/writing-style.md`: no metaphors, no
stories, no filler, plain words, short.
