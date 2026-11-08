With to case rewrite fails with else stab `(_ -> "")`
## Description
When trying to format code containing the pattern `(_ -> "")`, Styler 1.3.3 crashes with a FunctionClauseError.

## Environment
- Elixir: 1.18.1
- Styler: 1.3.3

## Error Message
```
** (FunctionClauseError) no function clause matching in Enum."-reduce/3-lists^foldl/2-0-"/3

    The following arguments were given to Enum."-reduce/3-lists^foldl/2-0-"/3:

        # 1
        #Function<44.12736194/2 in Code.Formatter.traverse_line>

        # 2
        {1, 456}

        # 3
        {:__block__, [closing: [line: 457], line: 457], [[{:->, [line: 457], [[{:_, [line: 457], nil}], {:__block__, [delimiter: "\"", line: 457], [""]}]}]]}
```

## Minimal Example
```elixir
with :ok <- can(current_user, _, _),
         do: email,
         else: (_ -> "")
```

## Expected Behavior
The formatter should handle this valid Elixir syntax without crashing.

## Actual Behavior
The formatter crashes with a FunctionClauseError when attempting to format this code.

### Additional contract requirements

- For `with :ok <- foo, do: :bar, else: (_ -> :baz)`, format it as:
```elixir
case foo do
  :ok -> :bar
  _ -> :baz
end
```
- - For `with :ok <- can(current_user, _, _), do: email, else: (_ -> "")`, format it as:
```elixir
case can(current_user, _, _) do
  :ok -> email
  _ -> ""
end
```
