# Lessons

`LESSONS.md` at a repo's root is where a session writes down what the owner
taught it, so the next session in that repo starts knowing it. It is committed,
and the repo's `CLAUDE.md` imports it, so every session in the repo loads it
whole at the start and keeps it whole through a compaction.

It exists because of a gap: a correction given in conversation lives only in
that conversation. A fresh session starts from the rules and the code, makes
the mistake the last session was corrected out of, and the owner corrects it
again. A long session loses the same correction when it is compacted, since a
summary keeps the task and drops the details. A line in a file loaded every
session is lost in neither case.

## What it is not

- **Not the rules.** A correction that holds in every repo belongs in a rules
  file. This file holds what holds in this repo.
- **Not `.decisions.md`.** That records a choice between options for one
  branch's pull request body. This records what a later session must do
  differently.
- **Not a log of the work.** No progress, no narration, no record of who said
  what or when. Each line is an instruction a session can follow.
- **Not the code's documentation.** A lesson the code, a test or a check now
  enforces is removed, since the enforcement carries it from then on.

## The format

The whole file, always:

```
# Lessons

## This repo
- <what to do, and the mistake it replaces>

## <a feature being built, in the words its issues' Part of uses>
- <what was settled, and the option it was settled over>
```

`This repo` always comes first and holds lessons for any work in the repo. A
feature section follows for each feature plan whose units are still being built,
headed with the feature's name exactly as its task issues write it in
`Part of`, so a session working one of those issues finds the section by that
name.

One sentence per line, under the rule `~/.claude/rules/pr-body.md` sets. Write
it for a session that was not there: "Build each settings form on its own page,
not inline on the settings index" carries, "don't do that again" does not. Name
the thing done and the thing done instead, and stop.

## When to write a lesson (ironclad)

**The moment the owner corrects a session, before the next line of code.** A
correction is the owner saying the work went the wrong way: a wrong approach, a
wrong reading of the request, a rule applied wrongly, a change of direction.

Ask one question: would a fresh session in this repo make this mistake again?
If it would, write the lesson. If the mistake came only from this branch's
details, such as a typo or a misread line, write nothing.

When a lesson would hold in every repo, say so to the owner and propose the
rules file it belongs in, rather than writing it here.

## Feature decisions

A decision made while building one unit of a feature plan is also one the later
units have to keep, and `.decisions.md` is deleted when that unit merges. So
before a branch whose issue sits in a stage of a feature plan opens its pull
request, its `.decisions.md` entries are copied into that feature's section here,
each as one line saying what was settled and what it was settled over. The
section is created by the first unit that has a decision to copy.

**The pull request that builds a feature's last unit removes its section.** By
then every decision in it is in the code, and nothing still to be built reads it.

## Committing it

A lesson goes in its own commit, holding `LESSONS.md` and nothing else, so it
can be read and reverted apart from the code. A commit that only changes this
file is documentation, and the Commits check does not read it.

A repo with no `LESSONS.md` gets one the first time a lesson is written, and in
the same commit its `CLAUDE.md` gains the line `@LESSONS.md`, creating
`CLAUDE.md` when the repo has none.

## When a session starts

The file is loaded by the import, so a session does not read it separately.
A session working an issue whose `Part of` names a feature reads that feature's
section before writing its first test, and treats every line in it as settled.
Reversing one is a change of direction, which is the owner's to make, and the
reversal is written as a new line rather than an edit to the old one.

## Its life

Committed and kept. The file is pruned, not cleared: a lesson the code now
enforces is removed, and a feature section is removed by the pull request that
finishes the feature. Anything else stays until the owner says it no longer
holds.
