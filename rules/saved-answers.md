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

`SYMPHONY_REPO_ANSWERS_DIR` names another folder for the repo answers and the
review lists, and tests use it so they never touch `~/.config`.

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

`--settles` prints only the entries whose question shares at least half of the
search's words and at least half of its own words, leaving out common words.
The answer gate searches this way.

## A repo answer overrides the default

A repo entry with the same name as a default replaces that default, and the
search prints only the repo entry. A repo that runs differently from the rest
says so in its own file, and every other default still holds in it.

## Capturing answers

When the owner answers a question window, `answer-capture.sh` records each
question in that repo's review list, `~/.config/symphony/answers/<repo>.review.json`,
next to the repo's answers. An entry holds the question, the option the owner
chose or the text they typed, any notes they added, the date and a status.

The status is `answered` when the owner gave an answer, `unanswered` when the
window came back with no answer to that question, and `rejected` when the owner
rejected the window. Only an answered entry carries an answer.

A captured answer settles nothing until the owner approves it.

## Reviewing them

The owner runs this in the terminal, from inside the repo:

```
~/.claude/bin/answers-review.sh
```

It shows each waiting entry in turn, with its question and the answer it would
save, and asks for one letter:

- `a` approves it. It asks for a short name and adds the entry to the repo's
  answers under that name, replacing any repo entry with the same name. A name
  that matches a default replaces that default in this repo.
- `e` asks for new wording for the answer, then asks again.
- `d` drops it from the review list.

An entry with no answer cannot be approved until wording is edited in. Each
choice is saved as it is made, so stopping partway leaves the rest waiting.

## The answer gate

Before a question window reaches the owner, `answer-gate.sh` searches the repo's
approved answers and the defaults with the question's words, using `--settles`.

- When an entry matches, the question is refused. The refusal quotes the saved
  question and answer and tells the session to use that answer instead.
- When nothing matches, the question goes through.
- When the search fails, the question goes through with a one-line warning.
- A window holding several questions is left to the one-question gate.

The match is on words alone, so a saved answer can share words with a question
it does not settle. The refusal says so: rephrase the question to say why it
differs. The added words lower the share of the asked question's words that the
saved question holds, so the rephrased question gets through.
