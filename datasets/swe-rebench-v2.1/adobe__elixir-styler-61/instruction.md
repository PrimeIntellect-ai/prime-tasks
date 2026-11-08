Keyword list as sole argument in a pipe in a map: syntax error after formatting
## Versions

* Elixir: 1.15.0
* Styler: 0.8.1

## Example Input

```elixir
    %{
      a: Foo.bar(baz: true) |> Quux.quux()
    }
```

## Current output

```elixir
    %{
      a: baz: true |> Foo.bar() |> Quux.quux()
    }
```

## Expected output

```elixir
    %{
      a: [baz: true] |> Foo.bar() |> Quux.quux()
    }
```

### Additional contract requirements

- Also, format `foo(kwl: :arg) |> bar()` as `[kwl: :arg] |> foo() |> bar()`.
