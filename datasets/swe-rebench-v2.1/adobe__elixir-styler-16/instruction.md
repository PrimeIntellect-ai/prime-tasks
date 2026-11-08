[Bug] Invalid code produced when piping operator statement with parentheses into function
## Elixir / OTP Version

use `elixir --version`

## Current Behaviour

While debugging some code I wrote the following:

```elixir
(call(a, b) == 1) |> dbg()
```

`styler` output the following, invalid code:


```elixir
call(a, b) |> ==(1) |> dbg()
```

## Expected Behaviour

I would expect the output to remain unchanged, or resolve to this:

```elixir
dbg(call(a, b) == 1)
```

### Additional contract requirements

- Additionally, `(bar() == 1) |> foo()` must be rewritten as `foo(bar() == 1)`, and `x |> bar` must be rewritten as `bar(x)`.
