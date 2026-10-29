# Expert Handoff

When one of the owner's gems has an expert agent installed in a repo, the code
that expert owns is written by that expert. A session hands the work to it with
the Agent tool rather than writing it by hand.

It exists because sessions kept writing by hand what an installed expert
already covers, and the owner had to stop them and point at the expert each
time.

## Who an expert is

A gem ships expert agents through `the_local`, which installs them into a repo
as `.claude/agents/<gem>-develop.md`, `<gem>-info.md` and `<gem>-install.md`. An
expert counts as installed when its develop agent is in the repo or in the
repo's main clone.

## Which files an expert owns

An expert's front matter says what it covers in plain words, which no hook can
match against a path. So the files each gem's expert owns are listed as path
patterns in the owner's own config, never in this repo:

```
~/.config/symphony/experts/default.json   patterns for every repo
~/.config/symphony/experts/<repo>.json    patterns one repo adds
```

Each file maps a gem's name to a list of patterns, relative to the repo root:

```json
{
  "widget_ui": ["app/views/**/*.erb", "app/components/**/*.rb"]
}
```

`*` matches within one folder, `**/` matches any number of folders including
none, and `?` matches one character. `<repo>` is the folder name of the repo's
main clone, so every linked worktree reads the same file. A repo's own patterns
are added to the shared ones.

## What holds it in place

`expert-handoff.sh check` runs before every file edit and write. When the file
matches a gem's patterns and that gem's expert is installed, it refuses the edit
and names the agent to hand the work to. It lets the gem's own develop and
install agents through, since Claude Code names the agent type in the input of
every hook a subagent's tool call runs, and refuses the main session and every
other agent.

`expert-handoff.sh notice` runs when a session starts. For each gem in the
patterns files that the repo's Gemfile or package.json uses, and whose expert is
not installed, it adds one line to the session saying to install it with
`the_local`. It is a notice and blocks nothing.

## What it does not catch

- A file written by a shell command, such as a redirect or `sed -i`.
- A gem with no entry in the patterns files, since an entry is what marks a gem
  as one of the owner's.
- Code that belongs to an expert but sits in a file no pattern names.
