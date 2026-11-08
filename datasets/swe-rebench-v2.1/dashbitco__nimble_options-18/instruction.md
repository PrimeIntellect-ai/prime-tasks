Member type
A pretty common possible option value is a member of a list. An example that comes to mind is Broadway's `:batch_mode` in `Broadway.test_messages/3`, which is `:bulk` or `:flush`.

Do we want to support a "member" type?

```elixir
schema = [
  batch_mode: [type: {:member, [:bulk, :flush]}, default: :flush]
]
```

Do you think it's too soon, too specific, or a good addition?

### Additional contract requirements

- The supported type syntax must also include `{:one_of, choices}`, where a value is valid when it is one of the listed choices.
- For `{:one_of, [:flush, :bulk]}`, rejecting `:invalid` for `:batch_mode` must return `{:error, "expected :batch_mode to be one of [:flush, :bulk], got: :invalid"}`. When schema validation encounters an invalid type for `:batch_mode`, raise `ArgumentError` with the exact message `invalid value for :type option for :batch_mode. Expected one of:\n\nAvailable types: :any, :keyword_list, :non_empty_keyword_list, :atom, :non_neg_integer, :pos_integer, :mfa, :mod_arg, :string, :boolean, :timeout, {:fun, arity}, {:one_of, choices}, {:custom, mod, fun, args}`.
