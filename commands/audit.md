---
description: Audit a named section of a repo against the checks — one file you keep and a published report, with nothing posted and nothing filed
---

You are auditing code that has no pull request open. The output is a file I keep
and a report I read. Nothing is posted anywhere and nothing is filed.

**Read `~/.claude/rules/repo-audit.md`** — the target, the audit file, the
report, and the stamp are all there. The checks themselves are in
`~/.claude/rules/review-checks.md`.

You do not run the audit. **`audit-scribe` runs it**, always — spawn it with the
**Agent tool, `subagent_type: audit-scribe`**, one Scribe per section. It runs
context-free so it has to read the code instead of auditing from what this
session already believes about it.

## What you do

1. **Get the target down to a section before spawning.** A section is a
   directory, a module, or one area of the product. A whole repo does not fit in
   one pass and the Scribe will refuse it.

   If I name a repo, say so and ask which section — do not pick one for me. If I
   name something that turns out to be too large, the Scribe returns the numbers
   and narrower targets, and I choose from those.

2. **Spawn the Scribe** with the repo, the section, and where to write the audit
   file. Hand it nothing else — not your reading of the code, not what you think
   is wrong with it. Those are the parts it is supposed to derive.

3. **Report back**: the report link first, then the audit file path, then one
   line per check giving its state. Then stop. I am going to read it.

4. **Leave the file where it was written.** It is mine to keep, commit, move or
   delete. Do not add it to a commit, do not gitignore it, and do not clean it
   up.

## Rules

- **Nothing is posted and nothing is filed.** No pull request comment, no review,
  no issue, however obviously a finding deserves one. If I want an issue from a
  finding, I will ask.
- **Do not fix what the audit finds.** The audit names it; fixing it is separate
  work on its own branch.
- **Do not audit it yourself.** Not to check the Scribe, not because the section
  is small, not while waiting.
- **One section per run.** If I name several, audit them one at a time and show
  me each report before starting the next.

Write to the rules in `~/.claude/rules/writing-style.md`: no metaphors, no
stories, no filler, plain words, short.
