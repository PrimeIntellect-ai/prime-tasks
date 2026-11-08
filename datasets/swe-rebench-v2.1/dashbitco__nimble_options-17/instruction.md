Timeout type
`non_neg_integer | :infinity`

thoughts?

### Additional contract requirements

- For the `:timeout` option, invalid values must return these exact errors: `{:error, "expected :timeout to be non-negative integer or :infinity, got: -1"}` for `-1`, and `{:error, "expected :timeout to be non-negative integer or :infinity, got: :invalid"}` for `:invalid`.
- When reporting available types for an invalid option type, list them in this exact order: `:any, :keyword_list, :non_empty_keyword_list, :atom, :non_neg_integer, :pos_integer, :mfa, :mod_arg, :string, :boolean, :timeout, {:fun, arity}, {:custom, mod, fun, args}`.
