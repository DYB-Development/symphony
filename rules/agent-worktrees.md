# Agent Worktrees

A repo's main clone belongs to its owner. Every agent session does its work in a
linked worktree of the repo, never in the main clone.

Git calls the original checkout the main worktree, here the main clone, and each
checkout made from it with `git worktree add` a linked worktree.

It exists because the owner uses the main clone to pull in merged work and try
it out. An agent that edits files there, commits there, or switches its branch
changes what the owner is looking at, and the owner's pull changes what the
agent is working on.

## The rule

**Before changing anything in a repo, make a worktree and work in it.** A new
worktree sits next to the main clone, in a folder named after the clone and the
branch, with any `/` in the branch written as `-`:

```
git -C ~/projects/app worktree add -b feature/quotes ~/projects/app-feature-quotes
```

Every edit, test run and commit for that branch happens in that folder. Nothing
in the main clone is edited, and its branch is never changed.

A Rails app needs its own databases per worktree first. See
`~/.claude/rules/worktree-databases.md`.

## What holds it in place

`main-clone-gate.sh` runs before every file edit and every shell command, and
refuses the ones aimed at a main clone:

- A file edit or write to any path inside it.
- A git `commit`, `checkout`, `switch`, `merge`, `rebase`, `reset`, `stash` or
  `pull` run in it, whether from its folder, after a `cd` into it, or through
  `git -C`.

Reading files and running `git status`, `log`, `diff`, `fetch` and
`worktree add` there stay allowed, since those are how an agent looks at the
repo and makes its worktree.

The gate cannot tell an agent from the owner running Claude in the main clone,
so it refuses both. A shell command that writes a file without git, such as a
redirect or `sed -i`, is not caught, and the rule above still applies to it.
