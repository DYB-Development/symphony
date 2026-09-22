# Worktree Databases

Every git worktree of a Rails app gets its own development and test databases.

It exists because worktrees of one app otherwise share one development
database. A branch migrated in one worktree changes that database for all of
them, and the next `db:migrate`, `db:prepare` or `bin/setup` in another worktree
writes that branch's schema into its `db/schema.rb`. The result is a
`db/schema.rb` changed by nobody on that branch, and a `git pull` that refuses
to run until it is discarded.

## The fix

```
~/.claude/bin/worktree-db.sh [<app-dir>]
```

It rewrites `config/database.yml` so each development and test database name
carries a suffix. The main clone's suffix is empty, so it keeps the databases it
already has. A linked worktree's suffix is its folder name, so a worktree at
`shop-console` uses `shop_development_shop_console`. Staging and production are
left alone. Running it on a config it already converted changes nothing.

## When to run it

**Before creating a worktree of a Rails app, check its `config/database.yml`.**
If the file does not start with the `worktree` line the script writes, the app
has not been converted yet:

- Run the script in the app's main clone, on a feature branch.
- Open the pull request for that change on its own, before any other work.
- Once it merges, each existing worktree pulls it and runs
  `bin/rails db:prepare` to create its own databases.

A new worktree starts with empty databases, so it runs `bin/rails db:prepare`
before its first server start or test run. Seed data from the main clone does
not carry over.

## If it already happened

A `db/schema.rb` changed by a migration from another worktree holds nothing from
this branch. Stash it or restore it from `HEAD`, pull, and run
`bin/rails db:migrate` to bring the database up to date with this branch.
