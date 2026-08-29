# Symphony

Context-free agents that write the documents around code — issues, pull request
bodies, feature plans, code reviews and repo audits — each to a fixed set of
rules, and each stamped with the versions that produced it.

Every agent here is spawned in isolation. It cannot narrate work it remembers
doing, because it did not do any: it has to read the diff, the repo, or the
issue. That is the whole idea, and it is why what comes out describes what is
actually there.

## What is in it

| Agent | Writes |
|---|---|
| `issue-scribe` | One standalone issue from a spec |
| `pr-scribe` | A pull request body, from the real diff |
| `plan-scribe` | A feature plan in four stages, from reading the repo |
| `review-scribe` | A pull request review, drafted before it is posted |
| `audit-scribe` | An audit of a section of a repo, with no pull request open |

They share one list of checks in `rules/review-checks.md`, one writing style in
`rules/writing-style.md`, and one stamp generator that names the versions behind
every document.

Three commands drive them: `/feature-plan`, `/review` and `/audit`.

## Setting it up

Clone this repo, then link it where Claude Code looks:

```sh
git clone https://github.com/tylercschneider/symphony.git
cd symphony

ln -sfn "$PWD/rules"    ~/.claude/rules
ln -sfn "$PWD/agents"   ~/.claude/agents
ln -sfn "$PWD/bin"      ~/.claude/bin

mkdir -p ~/.claude/commands
ln -sf "$PWD"/commands/*.md ~/.claude/commands/
```

Rules under `~/.claude/rules` are read in every session on the machine, so the
writing style and the development process apply everywhere, not only here.

The commands are linked file by file rather than as a directory, so your own
commands can live alongside these.

Back up anything already at those paths first — the links replace it.

## Running the tests

```sh
./run_tests.sh
```

Every file named `*_test.zsh` anywhere under the repo root is a suite and is
picked up with no registration.

## Two things to know

**Nothing here posts without being read first.** A review is drafted, rendered
for a person, and posted only when they say so. An audit posts nothing at all
and files nothing — it leaves a file and a report, and what happens next is
decided by a person.

**Nothing here merges or approves.** A review is always a comment.
