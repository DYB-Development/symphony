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

## What a claim pointer holds

A scribe writes one pointer per claim, and a pointer says only what the tooling
cannot work out for itself. It never holds a quote, a commit or a line of code.

```json
{
  "draft": "<the draft file the claims are quoted from>",
  "claims": [
    {
      "text": "<the claim, word for word as the draft writes it>",
      "pointer": { "path": "app/models/quote.rb", "from": 42, "to": 44, "side": "RIGHT" }
    }
  ]
}
```

- `path` is the file, relative to the repo root.
- `from` and `to` are the first and last line, counting from one, and `to` is
  never before `from`.
- `side` is `RIGHT` for the pull request's head commit and `LEFT` for its base
  commit. Both commits are read from the pull request, never from the local
  branch.
- A pointer carrying a quote, a commit or any line content is rejected. Those
  are the tooling's to write, and a pointer carrying them is a claim resting on
  something a model typed.
- **Every claim carries its text word for word**, which is what ties it to the
  draft. A claim whose text is not in the draft fails, and rewording a sentence
  means writing its claim again.
- **Every claim carries a pointer.** A claim with none fails rather than passing
  unchecked.

## What the capture records

The capture resolves each pointer and writes what it read into the same file,
under that claim. Nothing else writes there.

```json
{
  "captured": {
    "commit": "<the full hash the lines were read at>",
    "lines": "<those lines, as they are at that commit>"
  }
}
```

- The commit is recorded in full, so the same lines can be read again later.
- A commit the clone does not have is downloaded first, and a download that
  fails refuses the capture rather than reading another commit.
- A pointer naming a file that is not at that commit, or a line range the file
  does not reach, is reported as unresolved.
- A source that cannot be read at all is reported as not captured. It is never
  reported as captured and never counted as resolved.
- The capture exits 0 when every pointer resolves, 1 when any does not, and 70
  when it could not read the source.

## What the judge is given

Once every pointer has resolved, a separate model run reads each claim beside
the evidence captured for it and says whether the evidence bears the claim out.
That judgement is the part no script can make.

It is given three things and nothing else:

- The draft, as a person will read it.
- Each claim, with the commit and the lines captured for it.
- The whole file those lines sit in, at that commit, so the code above and below
  them can be read. A file too large to hand over is cut to a window around the
  lines, and the claim records that it was cut.

It is given no tools, no settings and no servers, exactly as the draft reader
is. It never sees the instructions the scribe was given, the conversation behind
them, or the draft reader's reply. It runs nothing.

## What the judge returns

This shape and nothing else:

```
1. "<the claim, word for word>"
   Verdict: supported
   Why: <one sentence>

2. "<the claim, word for word>"
   Verdict: refuted
   Why: <one sentence>

Uncited:
- "<a sentence in the draft that states a fact and carries no claim>"

Standing: <how many claims did not stand>
```

- **supported** means the captured lines bear the claim out.
- **unsupported** means they neither bear it out nor contradict it.
- **refuted** means they contradict it.
- A sentence saying what someone wants, asks for or intends is never listed as
  uncited, and neither is a section pasted word for word from a script.
- The last line is always `Standing:` and a number. Nothing follows it.

Each verdict is written back into the claims file, beside the evidence it was
judged against, so a later reader sees the claim, the lines and the judgement
together.

