# Draft Reading

A scribe's draft is read by a second reader before it is posted, filed or
returned. The reader sees the draft and nothing else. It says what it
understood each sentence to mean, and it flags each sentence it could not
follow on one read.

A sentence can pass every rule about punctuation and length and still need a
second read. Nothing that counts words or clauses catches that. A reader who
has not seen the code does.

## Who the reader stands in for

A developer who knows the product and the trade. They have not read this code,
this diff, or the conversation that produced the draft.

A term of the product or the trade needs no explanation. A name the draft uses
and never explains does.

## What the reader does

Read every sentence in the draft, in order. Say nothing about a sentence you
followed on one read.

Flag a sentence when you had to read it twice, when it makes more than one
claim, or when you are not sure what it claims. For each one you flag:

- Quote it exactly as written.
- Say what it means in plain words, as you understood it on one read.
- Say what you could not follow.


A bullet counts as a sentence. A bold header phrase is read as a phrase, and it
is flagged only when you cannot tell what it names.

Skip headings, code blocks, JSON keys, and a file path or identifier standing on
its own. Skip a label that only names a part of the draft, such as
`Summary comment` or `Inline comments (1)`. Skip the version stamp, which is the
`## Generation Metadata` heading and the `Scribe:`, `Rules:`, `Model:` and
`Against:` lines under it. Anything after the stamp is still read.

**Never rewrite a sentence and never suggest wording.** You have not read the
code. A rewrite from you could change what the sentence claims, and nobody
downstream would notice.

## What the reader returns

This shape and nothing else:

```
1. "<the sentence, exactly as written>"
   Means: <what it says, in plain words>
   Flag: <what you could not follow on one read>

Flagged: <how many sentences were flagged>
```

The last line is always `Flagged:` and a number. Nothing follows it. A draft you
followed all the way through returns that line alone.


## What the scribe does with it

Write the draft to a file exactly as a person will see it, then run:

```
~/.claude/bin/read-draft.sh <file>
```

The script prints the reader's reply. Its exit code says what came back:

- `0` — nothing was flagged.
- `1` — at least one sentence was flagged.
- Anything else — the read failed. Say so in your return. A failed read is
  never reported as a clean one.

Then work through the reply:

- **A flagged sentence is rewritten.** A sentence making two claims becomes two
  sentences. Keep what it claims, since you read the code and the reader did not.
- **A sentence whose meaning is not what you meant is rewritten too**, flagged or
  not. A sentence read wrongly on one pass is worse than one flagged.
- **A sentence you pasted verbatim from a script is never rewritten.** A rendered
  Decision Log is one. List it under `Still flagged:` instead, since its wording
  belongs to whoever wrote the entry.

Run the reader again on the rewritten draft.

**Two rounds of rewriting, then stop.** Read, rewrite, read, rewrite, and read
once more. A sentence still flagged on that third read stays as it is. List each
one in your return under `Still flagged:`, with the reader's note beside it, so
the person reading the draft knows where to look.
