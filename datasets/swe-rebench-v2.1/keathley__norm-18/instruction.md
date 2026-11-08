Specifying that a value in a map or struct can be nil
It doesn't seem to be possible to specify that a value in map or struct can also be `nil`:

```elixir
conform(%{foo: nil}, schema(%{foo: spec(is_binary() or is_nil())}))
# => {:error, ["val: %{foo: nil} in: :foo fails: :required"]}
```

Am I missing something or is this a bug?
