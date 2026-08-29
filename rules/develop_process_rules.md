# Develop Process

The standard process for writing code across all projects. Default to these rules
unless a project explicitly overrides them.

---

## Diverging from this process

Read this process before starting work and follow it — it is the default for
every session. If a task genuinely calls for breaking one of these rules, do not
silently deviate: **PAUSE and ask for a one-time exception**, naming the rule and
why it should be set aside here. An exception is granted for that instance only —
it needs no doc or notes update — and then you continue. Do not treat a granted
exception as a standing change to the process.

---

## Test-Driven Development

TDD is the default for everything. Work one tiny cycle at a time:

1. **Write one test that asserts one thing.**
2. **Run it and watch it fail** — for the right reason. A test you never saw fail
   proves nothing.
3. **Write the minimum code to make it pass.**
4. **Run the test and watch it pass.**
5. **Commit.**
6. Repeat with the next test.

One assertion per test. One test per commit cycle. No batching multiple behaviors
into a single test or a single commit.

---

## Commits

- A commit is normally **two files: the test file and the code file.**
- When implementing or updating an interface (e.g. a new controller endpoint) a
  commit may touch more files (route + controller + view) — that is the minimal
  coherent unit for that interface, and it is allowed.
- Keep each commit focused on the one behavior the test describes.
- **Never rewrite commits unless explicitly told to.** No amend, no rebase, no
  force-push, no history editing. If we decide to change something, we change it
  moving forward with a new commit — never backward by rewriting history — unless
  told otherwise.

---

## What to Test

- **Test our own code only.**
- **Never test third-party code** — not a gem, not an API, not a framework. The
  only test that may reference a dependency is one that asserts *our system is
  correctly wired to it* (the integration boundary), never the dependency's own
  behavior.
- **Never test another interface inside a unit test.** A test covers one interface.
  The single exception is the smoke integration test described below.

---

## Smoke Integration Test

When implementing an interface, write **one smoke integration test** that exercises
the interface end to end and proves the pieces are connected. This is the one place
where touching more than the unit under test is expected and correct.

---

## Pull Requests

- **Always work on a feature branch and open a PR.** Confirm the target branch
  before any git operation (`git branch --show-current`).
- **Keep PRs small and manageable** — typically **no more than 8–10 files.**
- Keep the focus of a PR narrow. One concern per PR.
- **All tests pass before opening the PR.**
- **The linter and every other CI check pass before opening the PR.**
- Never start a new PR until the previous one is merged.

---

## Code Quality

- Follow Clean Code principles: small functions, clear names, no surprises.
- Follow SOLID principles. Readable by a human first.
- Keep it simple — no abstraction until a real need calls for it.
- Explicitly require libraries rather than assuming autoload.

## Assumptions

- **Never assume.** Do not make proclamations or suggestions about something you
  do not know to be fact. If you don't know, say so and find out — read the code,
  run the check, or ask — before asserting anything.
- **Code is the only source of truth for behavior.** Comments, issue text, PR
  descriptions, commit messages, and docs describe intent, not fact — they may
  be stale or wrong. Never make a claim about how something works from them.
- **Two valid sources, nothing else: the code, or the expert agent that owns it.**
  Either read the code yourself, or delegate to the specialist agent that is
  already an expert in that subsystem and let it implement the interfaces it owns,
  where such an agent exists. Prefer the owning expert for its own interfaces
  rather than reconstructing their behavior from the outside.
- **Never substitute an artifact for either.** A comment, issue, or doc is a hint
  to verify, never the basis for a claim or an implementation. If you don't have
  the code in front of you and no owning expert is handling it, go get the code
  before you assert or build.
- **Verify what you touch, not everything nearby.** These rules say go read the
  code before you claim something — they do not say survey the repo. The scope is
  what you are changing or about to claim something about. Reading wider than that
  isn't diligence; it fills the session with code that competes for attention with
  the task and pulls the work off course.

## Comments

- **Write self-documenting code, not comments.** Code should be clean and readable
  on its own. Names — of classes, methods, variables, and partials — carry the intent.
- **A comment is a smell.** If you feel a comment is needed, the code is either built
  wrong or needs refactoring (a clearer name, a smaller method, an extracted object or
  partial) so the intent is obvious without prose. Follow SOLID and this resolves itself.
- Do not leave explanatory headers on classes/methods, inline "what this does" notes,
  or section banners. Delete them and let the structure speak.
- **Never write a comment unless instructed to.** Clean code whose intent is
  understandable needs none; feeling compelled to comment is a signal the code is
  overengineered, overly coupled, or too complex — fix the code, not the prose.
- Narrow exceptions, kept rare: a genuinely non-obvious *why* (a workaround for an
  external bug, a legal/security constraint) and machine-readable annotations the
  tooling requires (e.g. `rubocop:disable`). Prefer refactoring over a "why" comment
  whenever you can.
