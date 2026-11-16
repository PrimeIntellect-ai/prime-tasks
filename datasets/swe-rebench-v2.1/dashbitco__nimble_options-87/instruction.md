How to validate a list of keyword lists
When trying to validate a list of keyword lists, I would assume the following would work:

```elixir
definitions = [
  my_items: [
    type: {:list, :keyword_list},
    keys: [key: [type: :string]]
  ]
]

NimbleOptions.validate!([
  my_items: [
    [key: "value"],
    [key: "value"]
  ]
], definitions)
```

But instead I'm met with the following errors
```
** (ArgumentError) expected a keyword list, but an entry in the list is not a two-element tuple with an atom as its first element, got: [key: "value"]
    (elixir 1.12.1) lib/keyword.ex:475: Keyword.keys/1
    (nimble_options 0.4.0) lib/nimble_options.ex:388: NimbleOptions.validate_unknown_options/2
    (nimble_options 0.4.0) lib/nimble_options.ex:376: NimbleOptions.validate_options_with_schema_and_path/3
    (nimble_options 0.4.0) lib/nimble_options.ex:409: NimbleOptions.reduce_options/2
    (elixir 1.12.1) lib/enum.ex:4251: Enumerable.List.reduce/3
    (elixir 1.12.1) lib/enum.ex:2402: Enum.reduce_while/3
    (nimble_options 0.4.0) lib/nimble_options.ex:402: NimbleOptions.validate_options/2
    (nimble_options 0.4.0) lib/nimble_options.ex:377: NimbleOptions.validate_options_with_schema_and_path/3
```

### Additional contract requirements

The supported way to validate a list of keyword lists is to embed the per-element
keyword-list schema directly in the `:list` subtype, using the
`{:keyword_list, keys}` or `{:non_empty_keyword_list, keys}` subtype form. For example:

```elixir
definitions = [
  my_items: [
    type: {:list, {:keyword_list, [key: [type: :string]]}}
  ]
]

NimbleOptions.validate!([my_items: [[key: "value"], [key: "value"]]], definitions)
```

Each element of the list is validated as a keyword list against the embedded `keys`
schema, and the validated (possibly updated) elements are returned in the result.

When an element of such a list fails validation, the returned
`NimbleOptions.ValidationError` has `key` set to the list option's key, `value` set to
the whole list, and a `message` of the form:

    list element at position <index> in <key> failed validation: <inner error message>

where `<index>` is the zero-based position of the failing element and
`<inner error message>` is the message produced while validating that element.
