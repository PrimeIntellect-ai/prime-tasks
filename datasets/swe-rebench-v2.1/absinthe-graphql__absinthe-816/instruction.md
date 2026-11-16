"Cannot return null for non-nullable field" present when error was specified
### Environment

```
Elixir 1.9.0 (compiled with Erlang/OTP 22)
```
```
absinthe 1.4.16 (Hex package) (mix)
absinthe_relay 1.4.6 (Hex package) (mix)
absinthe_plug 1.4.7 (Hex package) (mix)
```

### Expected behavior

According to [current GQL specification](https://graphql.github.io/graphql-spec/June2018) paragraph [6.4.4](https://graphql.github.io/graphql-spec/June2018/#sec-Errors-and-Non-Nullability) and [working draft of new GQL specification](https://graphql.github.io/graphql-spec/draft) paragraph [6.4.4](https://graphql.github.io/graphql-spec/draft/#sec-Errors-and-Non-Nullability).

>If the field returns null because of an error which has already been added to the "errors" list in the response, the "errors" list must not be further affected. That is, only one error should be added to the errors list per field.

That means, that when `non_null` field has nil value, but there is already an error related to that field, then `"Cannot return null for non-nullable field"` error should not be propagated.

For example, if query

```elixir
field :user, non_null(:user) do
  arg :id, non_null(:id)
  resolve fn args, resolution ->
   case authorize(args, resolution.context.current_user) do
    :ok
      # next steps
      {:ok, user}
    :error
      {:error, :unauthorized}
  end
end
```

returns `{:error, :unauthorized}` then errors list should contain only one error in response:
```
%{
  "data" => nil,
  "errors" => [
    %{
      "locations" => [%{"column" => 0, "line" => 2}],
      "message" => "unauthorized",
      "path" => ["user"]
    }
  ]
}

```


### Actual behavior

`"Cannot return null for non-nullable field"` present in errors list in response.

```
%{
  "data" => nil,
  "errors" => [
    %{
      "locations" => [%{"column" => 0, "line" => 2}],
      "message" => "Cannot return null for non-nullable field",
      "path" => ["user"]
    },
    %{
      "locations" => [%{"column" => 0, "line" => 2}],
      "message" => "unauthorized",
      "path" => ["user"]
    }
}
```
