---
description: Run one work item from dyb_web's Pipelines hub — claim it, run its script steps, hand each agent step to the agent it names, and stop where the owner is needed
argument-hint: <work item id>
---

You are running one work item through the pipeline drawn for it in dyb_web's
Pipelines hub. The hub decides which step comes next. A step counts as done only
once its result has been reported there.

Run every command below from a clone of the work item's repo. The pipeline script
finds the work item's branch and worktree from there.

`~/.claude/bin/pipeline.sh` runs every script step itself and calls no model. You
run it, and you do only what it stops for: an agent step, or the owner's step.

## What you do

1. **Claim the work item.**
   ```
   ~/.claude/bin/pipeline.sh claim <id>
   ```
   It prints the title and the first step. It carries on when this session
   already holds the work item. A refusal saying another session holds it ends
   the run: show the message and stop.

2. **Run the pipeline script.**
   ```
   ~/.claude/bin/pipeline.sh run <id>
   ```
   Its exit status says what happens next:
   - `0` — the work item reached its end. Show the line it printed and stop.
   - `10` — it stopped at an agent step. Go to step 3.
   - `11` — the pull request waits on the owner. Show the line it printed, which
     names the pull request, and stop.
   - `12` — it stopped at the watch step. Start the command it printed as a
     **background** command (`run_in_background`) and end your turn. It runs no
     model while it waits, opens the pull request in the owner's browser once
     every check passes, and reports the result to the hub. When it exits you
     are woken: show its last line, then go back to step 2.
   - `13` — the work item reached a Wait step. Show the line it printed, which
     names the time the work waits until, and stop. Do not claim the work item
     again: the hub has already let it go, and the next session to claim work
     takes it once that time has come.
   - `14` — the work item's run stopped on a loop. Show the line it printed,
     which names the step where the loop stopped, and stop. Do not claim the
     work item again or work around the stop: the hub has already told the
     owner, who decides what happens next.
   - anything else — show what it printed and stop. Never work around it.

3. **Hand the agent step to the agent it names**, on the model it names. The
   script printed `Agent:` and `Model:` lines. Spawn the agent with the **Agent
   tool**, `subagent_type` set to the agent, and `model` set from the model id:
   `claude-sonnet-…` is `sonnet`, `claude-opus-…` is `opus`, `claude-haiku-…` is
   `haiku`, `claude-fable-…` is `fable`.

   - **`builder`** — hand it the repo, the work item's worktree (the path `git
     worktree list` shows for the branch whose name starts with the id), the
     title, request and acceptance criteria the script printed, and this check
     command, with the clone's absolute path in place of `<clone>`:
     ```
     cd <clone> && ~/.claude/bin/pipeline.sh check <id>
     ```
     Write the report it returns, whole and unedited, to a file in a directory
     made with `mktemp -d`, then post it:
     ```
     ~/.claude/bin/pipeline.sh report <id> <file>
     ```
   - **`pr-scribe`** — hand it the repo, the branch, the worktree, and the work
     item's acceptance criteria written out, since there is no issue. Then
     report the step, which passes only when the branch has an open pull request:
     ```
     ~/.claude/bin/pipeline.sh report-pr <id>
     ```

   Then go back to step 2.

## Rules

- **Hand a step only to the agent it names**, and only to `builder` or
  `pr-scribe`. The script refuses an agent symphony does not define, and you
  never stand in for one.
- **Never do an agent's work yourself.** Not the build, not the pull request
  body, not when the work looks small.
- **Never merge, and never report the owner's step.** The script reports it once
  the pull request is merged or closed. After the owner merges, run this command
  again: it carries on, reports the merge, runs the finish step and ends the work
  item.
- **One work item per run.** A second work item is a second session.

Write to the rules in `~/.claude/rules/writing-style.md`: no metaphors, no
stories, no filler, plain words, short.
