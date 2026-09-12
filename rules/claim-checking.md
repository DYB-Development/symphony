# Claim Checking

Every scribe writes a claim ledger beside its draft. The ledger lists each
factual claim the draft makes and the evidence behind it. A script then compares
each piece of evidence with its source, with no model taking part.

It exists because a document can read well and still say something untrue. A
reader with only the draft cannot tell. A script holding the draft's own words
and the source they came from can.

## What counts as a claim

A factual claim states what something outside the draft contains. The code at a
commit, a ticket's acceptance criteria, a command's output and a linked page are
all outside the draft.

These are claims:

- A finding that says what a line of code does.
- A statement that a check found nothing.
- A ticked acceptance criterion.
- A statement about what a repo already contains.

These are not claims, and they carry no evidence:

- What someone wants, asks for, or intends to build.
- A recommendation, an option, or a decision someone made.
- A sentence pasted word for word from a script, such as a rendered Decision Log.

## What a ledger holds

One JSON file beside the draft, named after it. The same shape as the review
draft and the audit file, so one reader of this package meets one shape:

```json
{
  "draft": "<the draft file the claims are quoted from>",
  "claims": [
    {
      "text": "<the claim, word for word as the draft writes it>",
      "negative": false,
      "evidence": [
        {
          "kind": "lines",
          "repo": "<owner/repo>",
          "commit": "<the full commit the lines were read at>",
          "path": "<the file, relative to the repo root>",
          "from": 42,
          "to": 44,
          "quote": "<those lines, word for word>"
        }
      ]
    }
  ]
}
```

**Every claim carries its text word for word.** That text is what ties the claim
to the draft, so a claim whose text is not in the draft fails. Rewording a
sentence means editing its claim too.

**Every claim carries at least one piece of evidence.** A claim with none fails
rather than passing unchecked.

**A negative claim is marked `negative`.** It says that something is absent, so
its evidence is a search that came back empty rather than lines that exist.

## How a line citation is written

`kind` is `lines`. The citation names the repo, the full commit, the file, the
first and last line, and the exact text of those lines.

- The commit is a full hash, never a branch or a short hash. A branch moves, so a
  citation to one cannot be checked later.
- `from` and `to` are the first and last line, counting from one, and `to` is
  never before `from`.
- `quote` is the lines as they are at that commit, including their indentation,
  and the lines join with a newline.
- A quote that differs from the source by one character fails. There is no
  allowance for whitespace, because a claim about code is a claim about what the
  code says.

## How a criterion citation is written

`kind` is `criterion`. The citation names the ticket and quotes the criterion.

- `ticket` is the ticket the criterion was read from, as `owner/repo#number` for
  an issue or as its key for a tracker outside GitHub.
- `quote` is the criterion word for word, as the ticket writes it.
- A criterion that is not in that ticket word for word fails. A criterion
  reworded to read better in the draft is a criterion nobody can check.

## How a command citation is written

`kind` is `command`. The citation records the command and what it printed, and
the check runs it again and compares.

- `run` is the whole command, as it was run.
- `output` is what it printed, word for word.
- **Only a command that reads is allowed**: `git show`, `git log`,
  `git cat-file`, `git grep`, `git status`, `grep`, `rg`, `sed`, `awk`, `cat`,
  `head`, `tail`, `wc`, `ls`, `find`, `jq`, and `gh issue view`, `gh pr view` or
  `gh api` with no method but GET. Anything else is refused and never run.
- A command that writes a file, moves a branch, changes a ticket, or reaches
  anything remote beyond reading is refused, because a check must never change
  what it is checking.
- A command that runs the code, its tests, a type check, a linter or a build is
  refused as evidence. CI runs those, and their result is not a claim about what
  the code says.

## How a link citation is written

`kind` is `link`. The citation names the page and quotes the text it rests on.

- `url` is the page, and `quote` is the text taken from it, word for word.
- The check fetches the page and fails the citation when the quote is no longer
  on it.
- With no network the citation is reported as not checked. It is never counted
  as passing, because a page nobody could read proves nothing.

## What a negative claim rests on

A negative claim says something is absent, so it rests on searches rather than
on lines that exist.

- Every piece of its evidence is `kind` `search`, and a negative claim resting on
  anything else fails.
- A search names what it looked for in words, in `looked_for`, so a reader can
  tell a thorough search from a narrow one.
- `run` is the search command, from the readers list above, and `output` is empty
  because the search came back empty.
- A search that now finds something fails the claim, since what was absent is
  there.
