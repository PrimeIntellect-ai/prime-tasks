SDL export excess types
With the following schema:

```elixir
defmodule Schema do
  use Absinthe.Schema

  object :query_fields do
    field :foo, :integer
  end

  query name: "Query" do
    import_fields :query_fields
  end
end
```

I perform `mix absinthe.schema.sdl --schema Schema`

And it looks like all the objects that are used for fields import are also reflected in the SDL dump.
It happens on any level, not only on the schema level.

JSON schema works as expected. I believe this is because JSON schema dump uses introspection query and SDL simply dumps everything in the namespace.

### Environment

* Elixir version (elixir -v): Elixir 1.9.4
* Absinthe version (mix deps | grep absinthe): 1.5.0-rc.2

### Expected behavior

It should produce:

```graphql
schema {
  query: Query
}

type Query {
  foo: Int
}
```

### Actual behavior

But produces:

```graphql
schema {
  query: Query
}

type QueryFields {
  foo: Int
}

type Query {
  foo: Int
}
```
