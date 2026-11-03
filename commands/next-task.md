---
description: Start the next task cleanly — read state, take the highest-leverage open issue, follow the dev process, finish with whatever its type calls for
---

You are starting a fresh task cycle. Do these in order, no shortcuts:

1. **Read `start_here.md`** (repo root, if present) — it's a resume bookmark pointing at the in-progress issue and branch with a single next step. Then read the linked issue and `git status` for the real spec and progress.
2. **Read the dev process rules and follow them exactly for this whole cycle.** They live in one place — `~/.claude/rules/develop_process_rules.md` — as the single source of truth; read that file. If this repo has committed its own `develop_process_rules.md` that deliberately overrides them, prefer the repo's copy for that repo.
3. **Confirm `main` is clean and current**: `git checkout main && git pull`. If a previous PR is still open and unmerged, STOP and tell me — do not start a second PR.
4. **Find where this repo keeps its work**: `~/.claude/bin/work-store.sh show`. When its first line is `github`, go on with this step as written. When it is `dyb_web`, the work is a dyb_web work item, and the number I named, if any, is that work item's:

   - With a number named, take it with `~/.claude/bin/work-store.sh take <n>`. It claims the work item in production for this machine's session and prints it as production reads it.
   - With no number named, take the next one with `~/.claude/bin/work-store.sh take-next`. Production claims the next ready work item for this repo and prints it with its `id`, which is the work item's number from then on. Production never hands out a work item that still waits on open work, so never rank, filter or pick one yourself.
   - When no work is ready, `take-next` stops with production's message. Tell me that message and STOP.
   - A refusal stops you. A work item that waits on open work is refused with the names of what it waits on, and one held by another session says so. Tell me the message and let me decide.
   - Restate the work item's title and acceptance criteria back to me before starting, from what `take` or `take-next` printed.
   - Branch with the work item's own `branch`, never a slug of your own, since dyb_web finds the pull request by that name.
   - In step 6 hand pr-scribe the work item's number and say it is a dyb_web work item, never an issue number.
   - Skip the rest of this step.

   **If I named an issue, that's the issue.** `gh issue view <n>` and go — no listing, no digest, no scoring, no "here's what I'd have picked instead." I already made the call; ranking exists to choose for me, not to check me. Take it even if it's low priority, even if it looks like a leaf, even if something else scores higher. The only thing that stops you is the issue being labeled `blocked` — say what's blocking it and let me decide. Its `area:*` label (if any) becomes the active series subsequent calls continue. Skip the rest of this step entirely.

   **Otherwise, pick the next issue — stay in the series, rank by leverage.** Fetch a digest, not the backlog. Ranking needs numbers, labels, titles, and `Blocked by` edges — never the prose of issues you aren't taking:

   ```
   gh issue list --state open --limit 100 --json number,title,labels,body \
     --jq '.[] | "\(.number)\t\([.labels[].name] | join(","))\t\(.title)\tdeps:\([.body // "" | scan("Blocked by [A-Za-z0-9_./-]*#[0-9]+")] | join(" "))"'
   ```

   One line per issue, with the dependency edges already extracted. Do not re-fetch the raw bodies — pulling every open issue's Context and Acceptance criteria into this session is what makes a later cycle drift into the wrong task. Skip anything labeled `blocked`, and read *only that issue's* body to name its blocker so I can see why it's parked.

   Score every open, unblocked issue:

   ```
   score = priority_weight × (transitive_dependents + 1)
   ```

   - `priority_weight`: `priority:high` 3, `priority:medium` 2, `priority:low` 1. A missing `priority:` label counts as 1 — and say so, since ranking is only as sharp as the schema is rolled out.
   - `transitive_dependents`: how many open issues depend on this one, directly or through a chain — chase the `deps:` column of the digest (it captures cross-repo `Blocked by owner/repo#N` too). So an issue that unblocks others floats above a leaf of the same priority.
   - `type:` is **not** in the score. Type decides what work the issue calls for (step 6), never what it's worth.
   - Ties break **oldest first** (lowest number).

   Then select in this order:
   - **Infer the active series** so I continue the list I was on instead of jumping to a different set: `gh issue list --state closed --limit 1 --json number,labels` for the most recently closed issue. If it carries an `area:X` label and open, unblocked `area:X` issues remain, the series is `area:X` — take the **highest-scoring open, unblocked `area:X` issue**. Leverage orders the series; it never pulls you out of one.
   - **When that series is drained** (no open, unblocked `area:X` issue left), or the last closed issue had no `area:` label, or nothing is closed yet: take the **highest-scoring open, unblocked issue repo-wide**. If it carries an `area:*` label, that becomes the active series the next call continues walking.
   - If **every** open issue is `blocked`, STOP and tell me what's blocking each — don't start one anyway.
   - Show me the top few with their scores so the pick is auditable, then `gh issue view <n>` and restate its acceptance criteria back to me before starting.
5. **Work inside the issue's boundary.** The chosen issue carries the request, not an implementation — per `~/.claude/rules/issue-schema.md` it names what someone can do and never where it is built. So the acceptance criteria are the whole brief, and the code is where you learn how.

   - **Read `How it fits` first if the issue has one.** It is the unit's slice of a larger feature plan: the records this unit touches and one line placing it in the build order. It is there so a unit taken out of a ten-issue feature still knows what the feature is for. It names records, never files — find the code from the acceptance criteria as below, and where the section and the code disagree, the code is right.
   - **Find the code from the acceptance criteria.** Search for the behavior each one names, then read the file you land on and what it calls. That search is the job. Surveying the repo to build a picture nobody asked for is not.
   - **Stop searching once you can start.** You need the files you are about to change and what they call, nothing wider. Reading past that fills the session with code that competes with the task.
   - **An ambiguous acceptance criterion is a question, not a search.** If a criterion could be satisfied two materially different ways, say so and ask — the issue is worth fixing at the source. Code you cannot find after an honest search is the same question.
   - **Don't open other issues.** Not to compare, not for background, not to check whether something is already covered. If one genuinely matters here it's wired as `Blocked by #N`, and step 4 already caught it.
   - **The acceptance criteria are the finish line.** Satisfy them and stop. Not the adjacent refactor, not the tidier design you noticed on the way, not the thing you got curious about while searching.

   **Record a decision the moment it is made, not at the end.** Whenever a choice between real options gets settled — where state goes, what boundary logic sits behind, a dependency taken or refused, a pattern deliberately broken, a scope line drawn, or any point where I choose between options you laid out — write it down before the next line of code with `~/.claude/bin/decide.sh "<question>" "<decision>"`. It appends to `.decisions.md`, which is gitignored and never reaches the issue or the diff; the PR Scribe reads it to write Decision Log, so a decision left unwritten is a decision the PR cannot report. The rules live in `~/.claude/rules/decision-log.md`. Most cycles have only one sensible option and record nothing — never pad the log to make the PR look considered.

   **When you find something outside that boundary — note it, don't fix it.** A real defect that isn't in the acceptance criteria gets one line in the PR body — hand it to the Scribe as an out-of-scope note — and an offer to file an issue. Fixing it here inflates a small PR into an unreviewable one and buries the change I actually asked for.

   **Two failed attempts at the same thing = stop and tell me.** If a test won't go green, a build won't work, or a fix won't hold after two honest tries, report where you are and what you tried. Do not widen the search, do not start rewriting neighboring code to make it pass, do not go looking for a deeper root cause to justify the struggle. Almost every long thrash starts as a small failure that was worth one sentence to me and got a rewrite instead.

6. **Do the work the issue's `type:` calls for.** The deliverable follows the type, per `~/.claude/rules/issue-schema.md` — don't force a PR onto an issue that shouldn't produce code.

   - **`type:task` · `type:bug` · `type:chore` → code + tests + PR.** Branch off fresh `main` (`git checkout -b feat/<short-slug>`, or the work item's own `branch` in a dyb_web repo, then confirm with `git branch --show-current`), build in TDD cycles one commit per behavior, run the linter and full suite, watch every CI check go green, then push the branch and spawn the **PR Scribe** (`Agent` tool, `subagent_type: pr-scribe`) with the repo, the branch, and the issue number, or the work item's number in a dyb_web repo — it reads the diff and opens the PR against `main`. Never hand-write the body. A bug also gets a regression test.
   - **`type:breakdown` → N standalone `type:task` issues, no production code.** Slice the source plan, then spawn one **Scribe** per issue (`Agent` tool, `subagent_type: issue-scribe`) with every bit of context inlined — the standalone rule is ironclad. Prioritize them, wire `Blocked by #N` dependencies, link them back to the breakdown issue, then close it. No branch, no PR.
   - **`type:plan` → the plan written into the issue body itself, no production code.** Options, tradeoffs, recommendation, risks — edited into the issue (`gh issue edit <n>`), never a committed `.md`. Finish by filing the `type:breakdown` that slices it. No branch, no PR.
   - **`type:spike` → time-boxed findings, no production code.** Post them as a comment on the issue and say what `type:plan` they feed. Hold the time box; if it blows, stop and tell me.
   - **`type:request` → not executable.** Don't build it. Offer to spin a `type:plan` from it (or close it if it's dropped) and let me choose.
7. **Handle the working-tree files**: if the issue's work is finished — PR merged, or the issues/plan/findings delivered — delete `start_here.md` and `.decisions.md` in the same step; if you're stopping mid-issue with unfinished work, leave `.decisions.md` in place and write the bookmark per the template in `~/.claude/CLAUDE.md` (Session Continuity). Don't accrete state into either.
8. **Stop at the gate** — if this cycle produced a PR, do not start the next issue until I merge it. If it produced issues, a plan, or findings, stop and let me look before you drain further.

If anything in `start_here.md` conflicts with the issues, trust the issues and flag the discrepancy.

Write to the rules in `~/.claude/rules/writing-style.md`: no metaphors, no
stories, no filler, plain words, short.
