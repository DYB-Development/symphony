---
description: Review a pull request — every check as inline comments, with a summary that links to them and checks the ticket's ACs
---

You are reviewing a pull request. The review is drafted first and posted only
after I have read it.

**Read `~/.claude/rules/pr-review.md`** — the comment format, the summary
sections, and how a re-review differs are all there. The checks themselves are
in `~/.claude/rules/review-checks.md`.

You do not write the review. **`review-scribe` writes it**, always — spawn it
with the **Agent tool, `subagent_type: review-scribe`**, one Scribe per pull
request. It runs context-free so it has to read the diff instead of reviewing
from what this session already believes about the code.

## What you do

1. **Work out which job this is** before spawning:
   - **review** — no review from us on the PR yet.
   - **re-review** — we reviewed it, the author pushed since, and I have asked
     for another pass.
   - **reply** — I want open comment threads answered, not a new review.

   Check with `gh pr view <n> --json reviews` if I have not said. When I name a
   PR with no other instruction, it is a review or a re-review, never a reply.

2. **Spawn the Scribe** with the repo, the PR number, and the job. Hand it
   nothing else — not your reading of the diff, not what you think is wrong with
   it, not the issue's acceptance criteria. Those are the parts of the review it
   is supposed to derive, and handing it yours is how a review comes back
   confirming a guess instead of checking one.

3. **Show me the rendered draft it returns**, whole and unedited, then stop. Do
   not summarise it, do not rank its findings, do not tell me which you agree
   with.

4. **Post it when I say so**, with the command the Scribe returned:

   ```
   ~/.claude/bin/review-draft.sh --post <owner/repo> <n> <file>
   ```

   Then delete the draft file and give me the review url.

5. **If I cut findings first**, edit them out of the draft file and renumber the
   `{{comment:N}}` tokens in the summary to match. Never reword a comment the
   Scribe wrote — cut it whole or post it as written.

## Rules

- **Never approve, never request changes, never merge.** Every review posted is
  event COMMENT. Those three are mine.
- **Do not review it yourself.** Not to check the Scribe, not because the diff
  is small, not while waiting.
- **Do not fix what the review finds.** The review names it; the author changes
  it. If the PR is mine and I ask you to fix a finding, that is a new task on
  its own branch.
- **One PR per run.** If I name several, review them one at a time and show me
  each draft before starting the next.

Write to the rules in `~/.claude/rules/writing-style.md`: no metaphors, no
stories, no filler, plain words, short.
