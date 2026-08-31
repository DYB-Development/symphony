# Repo Audit

An audit runs the checks over code that has no pull request open. It leaves one
file the person who ran it keeps, and one published report rendered from that
file. It posts nothing and it files nothing.

`~/.claude/rules/review-checks.md` defines what an audit looks for.
`~/.claude/rules/pr-review.md` governs the other consumer of that list, a pull
request review. This file governs what an audit reads, what it writes, and what
its report says.

## What an audit takes as its target

**A named section of a repo, never a whole repo.** A section is a directory, a
module, or one area of the product. Size is not what makes something a section —
a scripts directory of seven files and a models directory of two hundred are both
sections, and the thresholds below are a ceiling rather than a target.

A whole repo does not fit in one pass. A real application repo runs to millions
of tokens of source across thousands of files, so an agent asked to audit one
either fails or quietly reads a fraction of it and reports as though it read all
of it. The second is worse, and refusing is what keeps an audit's coverage a
fact rather than a hope.

**Measure the target before reading it.** Count the files and the bytes under
it. Past roughly 400 files or 1.5 MB of source, the section is too large — refuse
it, say what the numbers were, and name narrower targets inside it. Those
thresholds are a starting point and move once a few real audits have run.

Auditing a whole repo by splitting it across several scribes and merging their
files is a separate piece of work, and it is not this.

## What an audit writes

One JSON file per run, at a path the caller names:

```json
{
  "target": { "repo": "owner/repo", "commit": "a1b2c3d", "section": "app/models" },
  "measured": { "files": 34, "bytes": 210400 },
  "rubricVersion": 1,
  "wroteBy": { "scribe": "4e655ad", "rules": { "repo-audit": "4e655ad", "review-checks": "4e655ad", "audit-rubric": "4e655ad" }, "model": "claude-opus-5" },
  "checks": [
    {
      "check": "Security",
      "state": "findings",
      "findings": [
        {
          "area": "quoting",
          "path": "app/models/quote.rb",
          "line": 42,
          "summary": "…",
          "fix": "…",
          "cost": "moderate",
          "horizon": "now"
        }
      ]
    },
    { "check": "Scalability", "state": "nothing-found", "findings": [] },
    { "check": "Patterns", "state": "nothing-to-check", "findings": [] }
  ]
}
```

**Every check appears, named and ordered as `review-checks.md` names and orders
them**, and reported as that file says to report it. `state` carries its result,
spelled `findings`, `nothing-found` or `nothing-to-check`; what those mean and
why every check appears are in that file and are not restated here.

The eight parts an audit file carries, in this order:

`Security`, `Scalability`, `Design`, `Patterns`, `Dependencies`, `Tests`,
`Failure modes`, `Migration safety`.

Adding a check there means adding it here, and the suite fails if the two ever
disagree.

**Every finding names a file and a line.** A finding you cannot point at is not
a finding, and it does not go in the file.

**Every finding names the area it was found in.** An area is the part of the
product the code belongs to, in the words a person would use — `quoting`,
`billing`, `deploys`. It is what a score is computed per, and what two audits are
compared per, so the same code called the same area twice is the whole point.
Reuse an area name the section already implies rather than coining a second
spelling for it.

**Every finding carries a cost band and a horizon**, both assigned from
`~/.claude/rules/audit-rubric.json` — the cost band for what living with it
costs, the horizon for when that cost lands. Assign them from the meanings that
file gives, never from a feel for the number, and never write a score: the file
records the two bands and a script computes everything else from them.

**The file records the rubric version that scored it.** Two audits written under
different versions are not comparable, and the version is what makes that
checkable rather than assumed.

**The file carries the same versions the report's stamp names.** The file is the
source, so a reader holding only the file can still tell which scribe, which
rules and which model produced it. The report renders them as the stamp; the file
records them as `wroteBy`.

## What the report says

An artifact rendered from that file and from nothing else, so the two say the
same thing. It carries the target, the measurement, what each area costs, one
part per check in the same order, and the stamp.

**The area scores are computed, never written.**
`~/.claude/bin/audit-score.sh <file>` prints each area's score and the number of
findings behind it, and the report shows what it printed. A lower score means
that area costs less to carry than one with a higher score. The number is
unbounded, because there is no total to be a fraction of — it is what the area
costs at the moment it was measured, not a balance.

Given an earlier audit of the same section,
`audit-score.sh <earlier> <later>` prints what each area moved by, and that goes
in the report too. It refuses two audits scored under different rubric versions,
since their numbers mean different things.

The file is the source. When an audit is re-run the file is written again and
the report is published again from it — the report is never edited on its own.

## What an audit never does

- It posts no pull request comment and leaves no review.
- It files no issue and edits none.
- It changes no code in the target.
- It carries nothing forward from an earlier audit, gives no finding an identity
  across runs, and marks nothing resolved. Each audit is one measurement of the
  section at one moment.

What happens to a finding is decided by a person reading the report.

## One sentence means one sentence

The rule from `~/.claude/rules/pr-body.md` applies to every finding's summary and
every fix. One sentence each, one period, no semicolon. And
`~/.claude/rules/writing-style.md` applies to every word.

## The version stamp

Every report ends with a stamp naming the versions that wrote it, below the last
part, under a `---` rule:

```
---
## Generation Metadata

Scribe: audit-scribe `4e655ad`
Rules: repo-audit `4e655ad`, review-checks `4e655ad`, writing-style `0426b47`
Model: `claude-opus-5`, cc `2.1.246`

Audited Against: `acme/quotes@a1b2c3d`
```

It is **generated, not written**: `~/.claude/bin/scribe-stamp.sh audit
"<model-id>"` prints it and the Scribe pastes it verbatim. Never type a version
by hand. `Audited Against` is the repo and commit the section was read at, which
is what tells a reader months later whether the audit still describes the code.

A `+` there means the **whole tree** was dirty when the audit ran, not that the
audited section was. An uncommitted file somewhere else in the repo puts a `+` on
an audit of code that was clean, so the `+` is a reason to check rather than a
statement about the section.
