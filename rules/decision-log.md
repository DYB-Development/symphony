# Decision Log

`.decisions.md` at the repo root is where a decision made *while working* gets
recorded, the moment it is made. It is a working-tree file, globally gitignored,
and it never reaches a commit, a diff, or an issue. The PR Scribe reads it to
write the **Decision Log** section of the PR body.

It exists because of a gap: the Scribe is context-free by design, so a choice
settled in conversation is invisible to it. It can only
reverse-engineer decisions the diff happens to expose, and a decision's whole
value is the option that was *not* taken — which by definition leaves no trace
in the code. The log is that trace.

## What it is not

- **Not an issue comment.** An issue is the spec going in; it does not need to
  know how the work went. Nothing about the work flows back into it.
- **Not a committed doc.** Decisions about a branch die with the branch. What
  survives is the PR body.
- **Not `start_here.md`.** That is a resume bookmark saying where to pick up.
  This is a record of choices, and the two never merge into one file.
- **Not a log of the work.** No progress, no what-I-tried, no test results, no
  narration. One question, one answer.

## The format

The whole file, always:

```
# Decisions

## <the question, as a question>
<the answer, one sentence: what was chosen, and what it was chosen over>

## <the next question>
<the next answer>
```

Append-only, oldest first. Never edit or delete an entry that is already there —
a decision that gets reversed is a **new entry** whose question says so, exactly
like a commit that changes course rather than a rewritten history.

**Write both halves for the reviewer, not for yourself.** An entry reaches the
PR body **verbatim** — `decide.sh --render` prints the Decision Log section
straight from this file and the Scribe pastes it without editing a word. Nobody
downstream will fix your phrasing, so the entry is final when you write it. The
question has to stand on its own months later, to someone who was not here:
"Where should a decision made while working be recorded?" carries; "which one?"
does not.

One sentence per answer, under the same rule the PR body lives by: one period,
no semicolon, no trailing em-dash clause, no code, no file paths. Name the
choice and the option it was made over and stop. The argument for it is not recorded —
if it needs an argument, that is a comment on the diff.

## When to write an entry (ironclad)

**The moment a choice between real options is settled, before the next line of
code.**
Not at the end of the cycle, not when the PR is opened, not from memory. A
decision written later is a decision reconstructed, which is the exact failure
the Scribe exists to prevent.

A choice earns an entry when someone could reasonably have gone the other way:

- Where state is put, or what boundary logic sits behind.
- A dependency taken, or refused.
- An existing pattern deliberately broken.
- A scope line drawn — something real, deliberately left for elsewhere.
- Any point where I chose between options you laid out, or overruled your
  recommendation.

It does not earn an entry when there was only one sensible option. Most cycles
record nothing, and an empty log is the honest default — never pad it to make
the PR look considered.

## Writing one

```
~/.claude/bin/decide.sh "<the question>" "<the decision>"
```

The script creates the file if it is missing, appends the entry, and does
nothing else. Use it rather than hand-editing so the format cannot drift.

## What holds it in place

The rule above is not left to memory. Two hooks enforce it:

- Answering one of my questions arms a gate, since choosing between options I
  laid out is a choice between real options by definition.
- The next `git commit` is refused until `.decisions.md` has grown.

When the answer genuinely settled nothing a reviewer needs, say so out loud by
prefixing that commit with `NO_DECISION=1`. Reach for it when the question was
housekeeping, never to get past the gate on a real choice — the log is worth
nothing if the override is reflexive. Choices settled in conversation rather than
through a question are still mine to catch; no hook can see those.

## Its life

Created on demand during a cycle, read by the PR Scribe when the PR is written,
**deleted when the PR merges** — the same cleanup step that removes
`start_here.md`. This is required, not optional: the file describes one branch's
choices, so it must not survive into the next branch's work.
