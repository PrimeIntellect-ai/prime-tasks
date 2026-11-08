False positive in `Credo.Check.Refactor.Apply`
### Environment

* Credo version (`mix credo -v`): 1.7.7
* Erlang/Elixir version (`elixir -v`): 1.16.3
* Operating system: Linux

With the following snippet of code I get a `Credo.Check.Refactor.Apply` warning in functuion `foo2` (wrong) while no warning for function `foo1` (correct).

```elixir
defmodule A do
  def foo1(args) do
    apply(Bar, :baz, [1 | args])
  end

  def foo2(args) do
    apply(Bar, :baz, [1, 2 | args])
  end
end
```
