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
