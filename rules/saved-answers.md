# Saved Answers

The owner has already answered many of the questions a session would ask. Each
answer is saved with its question, so a session can find it instead of asking
again.

## Where they are

The answers are JSON files in two folders:

- `~/.claude/rules/answers/defaults.json` holds the answers that hold in every
  repo. It ships with this package, so it names no repo, client or host.
- `~/.config/symphony/answers/<repo>.json` holds one repo's own answers, where
  `<repo>` is the folder name of the repo's main clone, such as `shop`. These
  files live outside every repo and are never committed.

Each entry has a name, a question and the owner's answer. None of them is loaded
when a session starts.

## Searching them

Before asking the owner a question, search with its words:

```
~/.claude/bin/saved-answers.sh <the question's words>
```

It works out the repo from the current directory, so a linked worktree finds
the same answers as its main clone. It prints the repo's matching entries first,
then the matching defaults, at most five in all. An entry matches when its
question shares a word with the search, leaving out common words such as `the`
or `how`. When nothing matches it prints nothing and exits 1.

An answer it prints settles the question. Follow it rather than asking.

## A repo answer overrides the default

A repo entry with the same name as a default replaces that default, and the
search prints only the repo entry. A repo that runs differently from the rest
says so in its own file, and every other default still holds in it.
