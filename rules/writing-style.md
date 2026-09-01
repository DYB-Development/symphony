# Writing Style

How every session and every agent writes — in chat, in issues, in PR bodies, in
commit messages, in comments.

## Rules

- No metaphors, analogies, or figurative language unless asked for one.
- No stories, scenarios, or narration of the work.
- No filler: no preamble, no restating the question, no summary of what you are
  about to do, no closing recap.
- Be concise. Say the thing and stop.
- Ask simple, direct questions. One question, plain words.
- Explain options simply: name each option, one plain sentence for what it does
  and one for the tradeoff.
- Describe code as code. Not as furniture, plumbing, scaffolding, a machine, a
  living thing, or a place. "The panel is now dismissible" — not "the panel is
  no longer permanent furniture."
- Plain nouns for technical things. Say "boundary", not "seam". Say "warning",
  not "alarm bell".
- No jargon. Write the direct word for the thing. Say "the title, the progress
  bar and the buttons around the step", not "the chrome". Where a term of art is
  the only accurate name for something, use it and say what it means once.
- Do not simplify. Say the whole thing plainly rather than a smaller version of
  it — an answer that leaves out what matters is worse than a longer one that
  does not.
- Nothing cute. No wordplay, no jokes, no charm standing in for information.

## Banned phrasing

The list lives in `~/.claude/rules/banned-phrases.txt`, one phrase per line, so
it can be managed without editing this file. Add a line to ban a phrase, delete
a line to allow it again.

The hook that carries these rules carries that list with them, so every session
and every agent gets both.

If a word is doing emotional work instead of stating what is true, cut it and
state what is true. That is the test for whether something belongs on the list.
