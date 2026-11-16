@desc does not work for field arguments
### Environment

* Elixir version (elixir -v): 1.7.3
* Absinthe version (mix deps | grep absinthe): 1.5.0-alpha.1

### Expected behavior

```
query do
  field :my_operation do
    @desc "My argument description"
    arg :my_arg, :integer
  end
end
```

I expect the `@desc` call to add a `:description` to the argument.

### Actual behavior

The `@desc` above an argument does not work, it appears to be completely ignored.

### Additional contract requirements

- When an argument has both `@desc "Desc Three"` and `description: "overridden"`, its description is `"Desc Three"`.
- An argument's public name can be set with the `name:` attribute; for example `arg :with_attrs, type: :boolean, name: "HasAttrs"` records an argument whose name is `"HasAttrs"`.
- `Absinthe.Schema.Notation` provides a public function `handle_arg_attrs(identifier, type, raw_attrs)` that returns a keyword list containing `:name` (the identifier converted to a string) and `:type` (when a type is supplied), and replaces a `:deprecate` entry with a `:deprecation` entry.
