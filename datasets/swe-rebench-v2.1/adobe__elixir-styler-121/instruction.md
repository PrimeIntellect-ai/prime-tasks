edge case: compile callback module attribute ordering
## Versions

* Elixir: `Elixir 1.16.0 (compiled with Erlang/OTP 26)`
* Styler: `locked at 0.11.5 (styler) ed924524`

## Example Input

```elixir
defmacro __using__(opts \\ []) do
  quote do
    import Phoenix.LiveView
    @behaviour Phoenix.LiveComponent
    @before_compile Phoenix.LiveView.Renderer

    # Phoenix.Component must come last so its @before_compile runs last
    use Phoenix.Component, Keyword.take(unquote(opts), [:global_prefixes])

    @doc false
    def __live__, do: %{kind: :component, layout: false}
  end
end
```

## Stacktrace / Current Behaviour

```elixir
defmacro __using__(opts \\ []) do
  quote do
    @behaviour Phoenix.LiveComponent

    # Phoenix.Component must come last so its @before_compile runs last
    use Phoenix.Component, Keyword.take(unquote(opts), [:global_prefixes])

    import Phoenix.LiveView

    @before_compile Phoenix.LiveView.Renderer # <-- Problem line

    @doc false
    def __live__, do: %{kind: :component, layout: false}
  end
end
```

It's important to be able to place the [compile callback module attributes](https://hexdocs.pm/elixir/1.15/Module.html#module-compile-callbacks) in very specific places. Is there a workaround for this, or does there need to be a special case to handle `@before_compile`, `@after_compile` and `@after_verify`?
