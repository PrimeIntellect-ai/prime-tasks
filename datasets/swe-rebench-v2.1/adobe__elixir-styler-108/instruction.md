`with` handling seems to be broken in 0.11.0
## Versions

* Elixir: 1.15.7
* Styler: 0.11.0

## Example Input

```elixir
defmodule Foo do
  @moduledoc false
  def run(arg) do
    with value <- arg do
      value
    end
  end
end
```

## Stacktrace / Current Behaviour

```
foo$ mix format
** (Styler.StyleError) Error running style Blocks on lib/foo.ex
   Please consider opening an issue at: https://github.com/adobe/elixir-styler/issues/new
** (RuntimeError) unexpected `with` parent ast: {{:__block__, [line: 3], [:do]}, {:with, [do: [line: 4], end: [line: 6], line: 4], [{:<-, [line: 4], [{:value, [line: 4], nil}, {:arg, [line: 4], nil}]}, [{{:__block__, [line: 4], [:do]}, {:value, [line: 5], nil}}]]}}

    (styler 0.11.0) lib/style/blocks.ex:220: Styler.Style.Blocks.replace_with_statement/2
    (styler 0.11.0) lib/style/blocks.ex:79: Styler.Style.Blocks.run/2
    (styler 0.11.0) lib/zipper.ex:367: Styler.Zipper.do_traverse_while/3
    (styler 0.11.0) lib/styler.ex:37: anonymous fn/4 in Styler.style/3
    (elixir 1.15.7) lib/enum.ex:2510: Enum."-reduce/3-lists^foldl/2-0-"/3
    (styler 0.11.0) lib/styler.ex:35: Styler.style/3
    (styler 0.11.0) lib/styler.ex:65: Styler.format/3
    (elixir 1.15.7) lib/enum.ex:2510: Enum."-reduce/3-lists^foldl/2-0-"/3

Skipping style and continuing on
```

### Additional contract requirements

- Formatting the reported `with value <- arg do value end` case inside `def run(arg)` must complete without raising an unexpected-parent error.

- When `with value <- arg do value end` is the sole body of a zero-arity function, formatting must produce:

```elixir
def run do
  arg
end
```

When it is the sole body of an anonymous function, formatting must produce:

```elixir
fn ->
  arg
end
```
