Incorrect transformation
## Versions

* Elixir: Elixir 1.16.0-dev (7795adc) (compiled with Erlang/OTP 26)
* Styler: locked at 0.8.0 (styler) 32c76963

## Example Input

This code:

```elixir
  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:beacon_live_admin, 2}})
```

Gets transformed into:

```elixir
   defp expand_alias({:__aliases__, _, _} = alias, env),
     do: alias(Macro . :expand, %{env | function: {:beacon_live_admin, 2}})
```

## Stacktrace / Current Behaviour

```
** (SyntaxError) invalid syntax found on lib/beacon/live_admin/router.ex:112:23:
     ┌─ error: lib/beacon/live_admin/router.ex:112:23
     │
 112 │     do: alias(Macro . :expand, %{env | function: {:beacon_live_admin, 2}})
     │                       ^
     │
     syntax error before: expand
```
