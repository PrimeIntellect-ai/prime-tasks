styler doesn't pipe-ify pipes wrapped in a function call
## Versions

* Elixir: use `elixir --version`
* Styler: use `mix deps | grep locked | grep styler`

## Example Input

```elixir
# should get piped but doesn't, because the root node is not a pipe
a(b |> c |> d)

# correctly gets piped since the root node is a pipe
a(b(c)) |> d()
```

## Stacktrace / Current Behaviour

### Additional contract requirements

- When pipe-ifying the commented call below, the output must place the comments as shown:

```elixir
# d
# a
a
# b
|> b()
# c
|> c()
|> d()
```
