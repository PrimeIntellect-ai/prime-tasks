The –no-migration flag, does not prevent the generation of mirgrations when used with phx.gen.context
### Environment

* Elixir version 1.16.0:
* Phoenix version 1.7.19:
* Debian 12:

### Actual behavior

Inclusion of --no-migration flag in mix `phx.gen.context` command does not prevent generation of migration files.

```
mix phx.gen.context Testex Testa testas --no-migration
* creating lib/schem_exp/testex/testa.ex
* creating priv/repo/migrations/20250210111130_create_testas.exs
* creating lib/schem_exp/testex.ex
* injecting lib/schem_exp/testex.ex
* creating test/schem_exp/testex_test.exs
* injecting test/schem_exp/testex_test.exs
* creating test/support/fixtures/testex_fixtures.ex
* injecting test/support/fixtures/testex_fixtures.ex
```

> Remember to update your repository by running migrations:

`    $ mix ecto.migrate`

Please note generation of `priv/repo/migrations/20250210111130_create_testas.exs` as well as prompt to use command  `$ mix ecto.migrate`

### Expected behavior

It is stated that the default gen settings can be overridden with use of appropriate options.

The expected behaviour occurs when used with mix `phx.gen.schema`

```
mix phx.gen.schema Testa testas --no-migration
* creating lib/schem_exp/testa.ex
```

Excerpt from docs after running command mix help phx.gen.contexts


>     Default options
>
>     This generator uses default options provided in the :generators configuration
>     of your application. These are the defaults:
>
> config :your_app, :generators,
>   migration: true,
>   binary_id: false,
>   timestamp_type: :naive_datetime,
>   sample_binary_id: "11111111-1111-1111-1111-111111111111"
>
>     You can override those options per invocation by providing corresponding
>     switches, e.g. --no-binary-id to use normal ids despite the default
>     configuration or --migration to force generation of the migration.

Amending at the default level also produces expected behaviour with context as well as schema generation.

### Additional contract requirements

The context generator honors the application's `:generators` migration default. When that configuration sets `migration: false`, generating a context without an explicit migration-enabling option must not create migration files.
