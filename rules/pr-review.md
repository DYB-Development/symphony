# PR Review

What a review of a pull request looks like: inline comments where the problem
is, and one summary comment above them that says what was checked and what was
found. `~/.claude/rules/pr-body.md` governs the body the author writes; this
file governs what a reviewer writes back.

A review is short. It exists so the author knows what to change, so every
comment names one thing and says what to do about it.

## The checks

The checks themselves are defined in `~/.claude/rules/review-checks.md`, so that
one list serves every reader rather than living inside this one. Read it before
reviewing.

That file also says how a check is reported — that every one appears every time,
and what its three results mean. This file does not restate either, so adding a
check changes that file and no other.

## Conformance

A pull request that names a ticket is also checked against that ticket's
acceptance criteria. Read them from wherever the PR points — a GitHub issue in
the `Closes #N` trailer, a Jira key in the body or the branch name — and say for
each whether the diff covers it. A criterion the diff does not cover is a
finding in the summary, never an inline comment, because it is about what is
missing rather than about a line that is there.

With no ticket to read, the conformance section says `No ticket referenced.`
Never invent criteria from the PR body and check the diff against those.

## An inline comment

One finding, on the line that causes it. The whole comment:

```
**<Check> · <severity>** — <one sentence naming what is wrong>

<one sentence saying what to do instead>
```

- **Check** is the name of one of the checks, spelled as `review-checks.md`
  spells it.
- **Severity** is `blocking`, `worth fixing`, or `optional`. `blocking` means
  the PR should not merge as it stands, and it is reserved for a real defect —
  never for a preference.
- Two sentences, maximum. No paragraph of reasoning, no alternative designs, no
  praise, no question the author has to answer before they can act.
- A suggested change goes in a GitHub `suggestion` block under the two
  sentences, and only when the fix is exactly the lines being commented on.
- One comment per finding. The same problem in six files is one comment on the
  first, saying it repeats and where.

Never comment to say something is fine. Never comment on a line the diff does
not touch.

## The summary comment

The body of the review that carries the inline comments, so it sits above them
and every finding it names links to the comment that raised it. Always these
sections, in this order, and never another:

```
## Verdict

<one sentence: whether this is ready to merge, and what stands in the way if not>

## Findings

- **Security** — <one sentence, or "nothing found", or "nothing to check">
- **Scalability** — <one sentence, or "nothing found", or "nothing to check">
- **Design** — <one sentence, or "nothing found", or "nothing to check">
- **Patterns** — <one sentence, or "nothing found", or "nothing to check">
- **Dependencies** — <one sentence, or "nothing found", or "nothing to check">
- **Tests** — <one sentence, or "nothing found", or "nothing to check">
- **Failure modes** — <one sentence, or "nothing found", or "nothing to check">
- **Migration safety** — <one sentence, or "nothing found", or "nothing to check">

## Conformance

- [x] <the criterion, one sentence>
- [ ] <the criterion the diff does not cover, one sentence>

## Not checked

- <one sentence: what this review did not look at>
```

**Verdict** names blocking findings and nothing else. No summary of the diff, no
restating the title, no thanks.

**Findings** is one bullet per check, named and ordered as `review-checks.md`
names and orders them, and reported as that file says to report it. Adding a
check there means adding its bullet here, and the suite fails if the two ever
disagree. A bullet naming a finding links the words that name it to the comment
that raised it — `[the line item loop]({{comment:1}})`, where the number is the
comment's position in the draft. A bullet with no finding carries no link.

**Conformance** is one ticked or unticked box per acceptance criterion, in the
ticket's own order and words. With no ticket, its whole content is
`No ticket referenced.`

**Not checked** is what a reader would reasonably assume was covered and was
not — a test suite that was not run, a migration whose data was not looked at,
a file skipped because it is generated. Nothing to say means `Not relevant.`

The cap on findings is in `review-checks.md` with the rest of the reporting
shape.

## One sentence means one sentence

The rule from `~/.claude/rules/pr-body.md` applies to every bullet and every
inline comment here. One sentence, one period, no semicolon, no clause bolted on
the end. An inline comment gets two sentences because the second is the fix.

And `~/.claude/rules/writing-style.md` applies to every word. No metaphors, no
narration, no filler, no praise.

## The draft

A review is drafted before it is posted, and I read the draft first. The Scribe
writes it as one JSON file:

```json
{
  "summary": "## Verdict\n\n...",
  "comments": [
    { "path": "app/models/quote.rb", "line": 42, "side": "RIGHT", "body": "**Scalability · blocking** — ..." }
  ],
  "replies": [
    { "in_reply_to": 2145566, "body": "..." }
  ]
}
```

`~/.claude/bin/review-draft.sh --render <file>` prints it for reading, and
`--post <owner/repo> <pr> <file>` posts it once I say so. Posting puts the
inline comments up as one review, then makes the summary that review's body with
each `{{comment:N}}` token replaced by the url of the comment it names.

**A review never approves and never requests changes.** Every review posted is
event COMMENT; approving and merging are mine.

## Re-reviewing

A second pass over the same PR posts a fresh review rather than editing the
first. The earlier review is the record of what the code looked like then, and
rewriting it loses which findings the author actually fixed.

A re-review reads the commits since the last review and says so in its verdict:
what was raised before and is now fixed, and what still stands. A finding still
present gets a fresh inline comment on the current line, since the old one
points at a line that has moved.

## Replying to comments

Answering an existing thread is not a review and posts none. It is a reply on
the thread it answers, drafted in the same file's `replies` and posted the same
way.

A reply is one or two sentences. It says what was changed and names the commit,
or it says what will not change and why in one sentence. It never re-argues a
finding at length and never restates the comment it answers.

## The version stamp

Every summary comment ends with a stamp naming the versions that wrote it, below
the last section, under a `---` rule:

```
---
## Generation Metadata

Scribe: review-scribe `4e655ad`
Rules: pr-review `4e655ad`, writing-style `0426b47`
Model: `claude-opus-5`, cc `2.1.246`

Reviewed Against: `tylercschneider/quotes@a1b2c3d`
```

It is **generated, not written**: `~/.claude/bin/scribe-stamp.sh review
"<model-id>" <owner/repo>@<sha>` prints it and the Scribe pastes it verbatim into
the summary. Never type a version by hand. A `+` after a commit means that file
had uncommitted edits when the review ran. The model is named by its id, never
its display name.

`Reviewed Against` is the pull request's head commit at the moment of the
review — the code the findings are about, not the branch the Scribe's shell was
on — and it sits below the rest after a blank line. It is
what makes a stale review visible: a summary naming a commit the branch has
since moved past was written against code that no longer exists, and its
findings are answered by the diff rather than by the author. A re-review names
the new head, which is how the two reviews are told apart.

It is a trailer, not a fifth section. An inline comment carries no stamp — the
summary above it carries the one for the whole review.
