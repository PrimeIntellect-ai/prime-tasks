Warn on `.ex` files in `priv/repo/migrations`
### Elixir version

*

### Database and Version

*

### Ecto Versions

*

### Database Adapter and Versions (postgrex, myxql, etc)

*

### Current behavior

Right now correct-looking migration files in `priv/repo/migrations` get silently skipped if they're `.ex` files rather than `.exs`. See https://github.com/vinniefranco/exandra/discussions/52 for context.

### Expected behavior

I know that `mix ecto.gen.migration` generates correct filenames, but I’m wondering: should we just warn if there are `.ex` files in a migrations directory? Are there legit use cases for something like that?

### Additional contract requirements

- The warning written to stderr must include the exact text `file looks like a migration but ends in .ex` and the affected filename.
