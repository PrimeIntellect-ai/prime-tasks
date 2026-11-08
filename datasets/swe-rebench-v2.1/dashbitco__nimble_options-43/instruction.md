Proposal: add `integer` type
I was surprised to find that only `:non_neg_integer` and `:pos_integer` were supported, but this seems like a pretty common type that should be included by default. Thoughts?

### Additional contract requirements

- The new option type is named `:integer` and is accepted in the `:type` field of a `NimbleOptions.validate/2` schema.
- When a value supplied for an `:integer` option is not an integer, validation returns `{:error, %NimbleOptions.ValidationError{message: message}}` where `message` is `"expected <key> to be an integer, got: <value>"`, with `<key>` and `<value>` being the inspected option key and value.


- - When a schema contains an unsupported option type, the `Available types:` list in the `ArgumentError` message from `NimbleOptions.validate/2` must include `:integer`.
