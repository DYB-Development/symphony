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

Needs `git`, `zsh`, `jq`, and the GitHub CLI `gh` already authenticated.

```sh
git clone https://github.com/tylercschneider/symphony.git
cd symphony
./install.sh
```

That links `rules`, `agents` and `bin` into `~/.claude`, links each command into
`~/.claude/commands` one file at a time, and registers the hooks in
`~/.claude/settings.json`. Anything already at one of those paths is moved aside
to `<path>.backup` first, and running it again changes nothing. Set
`CLAUDE_CONFIG_DIR` to install somewhere other than `~/.claude`.

### What the links do

Rules under `~/.claude/rules` are read in every session on the machine, so the
writing style and the development process apply everywhere, not only here.

The commands are linked file by file rather than as a directory, so your own
commands can live alongside these.

### What the hooks do

Settings are merged rather than replaced, so hooks and settings you already have
are kept. Four entries are added:

| Event | Runs | Why |
|---|---|---|
| `SessionStart` | `writing-style-hook.sh` | Carries the writing rules and the banned phrase list into the session |
| `SubagentStart` | `writing-style-hook.sh` | A subagent receives no rules of its own, so it gets them here |
| `PostToolUse` | `decision-gate.sh arm` | Answering a question settles a choice, which has to be recorded |
| `PreToolUse` | `decision-gate.sh check` | Refuses a commit while that choice is still unrecorded |

Skip the hooks and the package still loads, but the writing rules never reach a
subagent and the decision gate never fires, both without saying so.

### Two more steps

The rules keep three working-tree files that must never reach a commit — the
decision log, the ticket reference and the resume bookmark. Add them to your
global gitignore:

```
.decisions.md
.ticket
start_here.md
```

Then, once per repo you use the issue schema in, create its labels:

```sh
~/.claude/bin/issue-bootstrap.sh
```

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
