# Worktree Databases

Every git worktree of an app gets its own development and test databases, for
two kinds of app: a Rails app and a package app.

It exists because worktrees of one app otherwise share one development
database. A branch migrated in one worktree changes that database for all of
them, and the next `db:migrate`, `db:prepare` or `bin/setup` in another worktree
writes that branch's schema into its `db/schema.rb`. The result is a
`db/schema.rb` changed by nobody on that branch, and a `git pull` that refuses
to run until it is discarded.

## The two kinds of app

**A Rails app** has a `config/database.yml` whose first line is the `worktree`
header `worktree-db.sh` writes. That header adds a suffix to each development
and test database name. The main clone's suffix is empty, so it keeps the
databases it already has. A linked worktree's suffix is its folder name, so a
worktree at `shop-console` uses `shop_development_shop_console`. Staging and
production are left alone.

**A package app** has a root `package.json` with two scripts:
`worktree:db:create`, which creates this checkout's development and test
databases, and `worktree:db:drop`, which drops them. The app names its own
databases with the same suffix rule, and both scripts run with Bun from the
worktree's root. Symphony runs them and knows nothing else about the app, so
the scripts must be safe to run twice, and the drop must refuse a main clone.

Postgres cuts a database name at 63 characters, so a long folder name is cut
short to fit the app's longest database name and ends in a short hash of the
full name. Two worktrees whose names differ only near the end still get
different databases.

## Converting a Rails app

```
~/.claude/bin/worktree-db.sh [<app-dir>]
```

It writes the header into `config/database.yml`. Running it on a config it
already converted changes nothing. An app converted before names were kept
short needs it run once more, which replaces only the first line of its config.

**Before creating a worktree of a Rails app, check its `config/database.yml`.**
If the file does not start with the `worktree` line the script writes, the app
has not been converted yet:

- Run the script in the app's main clone, on a feature branch.
- Open the pull request for that change on its own, before any other work.
- Once it merges, each existing worktree pulls it and creates its databases
  with the command below.

A package app has no conversion step. Its two scripts are added to the app
through its own pull request.

## Creating and dropping a worktree's databases

```
~/.claude/bin/worktree-databases.sh [--kind rails|package] create|drop <worktree>
```

**Run `create` right after making a worktree**, before its first server start or
test run. It prepares a Rails app's databases with `bin/rails db:prepare` and
runs a package app's `worktree:db:create`, for every app of either kind in the
worktree. A Rails app that has not been converted is reported and skipped. A new
worktree's databases start empty, and seed data from the main clone does not
carry over.

`--kind` limits either action to one kind of app, so one app's databases can be
recreated while the other's are kept. A create or drop that fails for one kind
names the kind and the worktree, still runs the other kind, and exits non-zero.

A worktree's databases are dropped when the worktree is cleaned up after its
branch merges, by `~/.claude/bin/worktree-done.sh`, which drops every kind. See
`~/.claude/rules/agent-worktrees.md`.

## If it already happened

A `db/schema.rb` changed by a migration from another worktree holds nothing from
this branch. Stash it or restore it from `HEAD`, pull, and run
`bin/rails db:migrate` to bring the database up to date with this branch.
