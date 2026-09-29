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

## When the branch is merged

**The moment its pull request is confirmed merged, the worktree is cleaned up.**
It is the same step that deletes `start_here.md`, `.decisions.md` and `.ticket`,
and it is required, not something to ask about:

```
~/.claude/bin/worktree-done.sh ~/projects/app-feature-quotes
```

The script removes the worktree, deletes its local branch, and drops the
development and test databases its app names, including the numbered copies
made for parallel tests. It refuses the main clone, a worktree with changes not
committed, and a worktree with commits not yet on the remote's main branch, and
in each case it changes nothing.

A worktree left behind after its branch merges keeps its databases, and those
build up into hundreds that nothing else will remove.

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
