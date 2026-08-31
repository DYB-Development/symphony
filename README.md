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
./install.sh --help
```

There are two ways to install it, and you want one, not both. Installing both
registers every hook twice, so whichever you run second refuses.

### Linked

```sh
./install.sh
```

Links `rules`, `agents` and `bin` into `~/.claude`, links each command into
`~/.claude/commands` one file at a time, and merges the hooks into
`~/.claude/settings.json`. Anything already at one of those paths is moved aside
to `<path>.backup` first, and running it again changes nothing. Set
`CLAUDE_CONFIG_DIR` to install somewhere other than `~/.claude`.

Commands are run as `/review`. A file edited in this clone takes effect in the
next session, with no reinstall, which is what makes this the mode to use while
changing the rules themselves.

### As a plugin

```sh
./install.sh --plugin
```

Registers this clone as a marketplace and installs it. Commands are namespaced,
so a review is `/symphony:review`, and updates come through
`claude plugin update` rather than `git pull`.

### What the links do

Rules under `~/.claude/rules` are read in every session on the machine, so the
writing style and the development process apply everywhere, not only here.

The commands are linked file by file rather than as a directory, so your own
commands can live alongside these.

### What the hooks do

The plugin carries its hooks itself. A linked install merges the same four
entries into your settings, replacing any it put there before, and leaving hooks
and settings that are not its own alone:

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

### Configuring it

Everything works unset. These change what the package reads, and they belong in
your own shell or settings rather than in a file here, so an update never
overwrites them.

| Variable | Changes |
|---|---|
| `CLAUDE_CONFIG_DIR` | Where the installer links to, instead of `~/.claude` |
| `CLAUDE_WRITING_STYLE_FILE` | The writing rules carried into every session, so you can supply your own voice |
| `CLAUDE_BANNED_PHRASES_FILE` | The phrase list carried alongside them |
| `AUDIT_RUBRIC_FILE` | The cost bands and horizons an audit is scored against |
| `ISSUE_BOOTSTRAP_OWNERS` | The accounts `issue-bootstrap.sh --all-repos` syncs labels across |
| `SYMPHONY_IDENTIFIERS` | A file of terms no shipped file may name, checked by the suite |

The two writing-style variables are how you replace the shipped voice without
editing a file the package owns. Each names a path, so what they point at can be
as long as you like.

`ISSUE_BOOTSTRAP_OWNERS` is empty by default and `--all-repos` does nothing until
you set it, because that flag writes to every non-archived repo of every account
named.

`SYMPHONY_IDENTIFIERS` is unset by default, so the suite reports nothing to check
and passes. A list of names cannot be kept here without carrying the names the
check exists to keep out.

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
