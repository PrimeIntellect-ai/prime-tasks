when de-piping an assignment, try to fit it on one line
## Example Input

```elixir
# given
x =
  y
  |> Enum.map(&f/1)
  |> Enum.join()

# we get
x =
  Enum.map_join(y, &f/1)

# we want
x = Enum.map_join(y, &f/1)
```
