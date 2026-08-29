# Review Checks

What a review of code looks for, defined once here and read by everything that
reviews. `~/.claude/rules/pr-review.md` governs how a pull request review is
written and posted, and `~/.claude/rules/repo-audit.md` governs how an audit is.
This file governs what both of them look for.

**Adding a check means adding it here first**, then naming it in each reader that
reports it — `~/.claude/rules/pr-review.md` and `~/.claude/rules/repo-audit.md`.
Only this file defines a check; they name it so a reader can see the list they
will get, and the suite fails if any of the three disagree.

**Every check applies to whatever it is pointed at** — an application, a script,
a configuration file, a workflow. Where a check names something that does not
exist in what you are reading, read it for what it is about rather than for its
example: a query in an application is a command in a script, an endpoint is an
entry point, a request is one run.

**Every finding is one sentence naming what is wrong and one saying what to do
instead.** A check that asks for several facts is asking for the one that makes
the defect clear, not for all of them.

## How a check is reported

**Every check reports, every time, in the order below.** A check with nothing to
say still appears, because a reader cannot otherwise tell a check that ran and
found nothing from one that was skipped. Three results, and the difference
between the last two matters:

- **a finding** — the check ran and found something.
- **nothing found** — the check ran against code it applies to and found nothing.
- **nothing to check** — what was read holds nothing it applies to, such as a
  migration check against code with no migrations.

Never omit a check, and never guess a result: a check you did not run has no
honest result to record, so run it.

**Six findings is the cap**, whatever the list grows to. Past that, what is being
read needs reworking rather than reviewing, and the honest move is to say so and
raise the six that matter.

## The checks

**Security** — a credential, token, key or connection string reaching the repo,
a log, an error message or anything sent outward; and data crossing a boundary
it should not, most often one team, tenant or account reading another's records
because a lookup was not scoped to the current one. Input reaching a query, a
command or a path without being constrained counts, and so does authorization
dropped from a way in.

**Scalability** — work that grows when the data does: a lookup inside a loop,
one call per row of a collection, a missing index behind something the new code
makes hot, an unbounded fetch, and work done every time that could be done once.
Name what it grows with.

**Design** — coupling that will make this hard to change: a caller reaching
past its boundary, a unit that has to know how another works, a single thing
holding several responsibilities, and an addition that will need editing in
several places. It is a finding when you can name the change that becomes
harder.

**Patterns** — new code doing something the rest of the repo already does
differently, when there is no reason for the difference. It is a finding only
when you can point at the existing pattern: the file that does it the other way.
A preference with no precedent in the repo is not a finding.

**Dependencies** — a dependency taken that need not have been, a second library
doing what one already there does, a version left unpinned, and a dependency
pulled in for one line of it. Name the one already there, or the line.

**Tests** — a test that passes for the wrong reason or fails for none: order
dependence, reliance on the clock or on randomness, a network call, a sleep, and
state shared between examples. Also a test that mirrors the implementation
instead of asserting behaviour, since it locks the implementation in and fails
on a refactor that changed nothing.

Also a behaviour the suite does not reach where the code gets it wrong. Name the
missing test and the defect together — that is one finding, and the fix is one
cycle: write the test, watch it fail, fix.

**Failure modes** — what happens when something outside this code fails: a
call, a job, a dependency, a disk, a network. A failure swallowed, retried
forever, or left half-applied is a finding, and so is one that cannot be told
apart from success.

**Migration safety** — a change to stored data that cannot be run safely: a
schema change against a table in use, a backfill that is not safe to run twice,
and a change that cannot be undone. Name what breaks if it runs while the old
code is still live.
