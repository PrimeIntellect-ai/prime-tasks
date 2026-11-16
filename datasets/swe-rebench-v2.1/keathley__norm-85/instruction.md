SpecError from selections direct attention away from the problem
```elixir
defmodule Extra do
  use Norm
  defstruct [:not_the_problem]
end

defmodule A do
  use Norm
  def assigns, do: schema(%{extra: schema(%Extra{})})
  def test, do: conform!(%{extras: %Extra{}}, selection(assigns(), :all))
end

A.test()
```
→
```
** (Norm.SpecError) key: :not_the_problem was not found in schema:
%{
  :not_the_problem => :
}

    (norm 0.12.0) lib/norm/core/selection.ex:56: Norm.Core.Selection.assert_spec!/2
    (norm 0.12.0) lib/norm/core/selection.ex:36: Norm.Core.Selection.select/3
    (norm 0.12.0) lib/norm/core/selection.ex:32: Norm.Core.Selection.select/3
    iex:70: A.test/0
```
→ wasting a whole bunch of time trying to figure out how `not_the_problem` could possibly be missing from a struct, when actually the problem is forgetting you meant the singular `extra` not the plural `extras`.

### Additional contract requirements

- For the tested case `selection = selection(schema(%{event: schema(%Event{})}))` and input `%{typo: %Event{}}`, `conform(input, selection)` must return `{:error, [%{input: %{typo: %Event{}}, path: [:event], spec: ":required"}]}`.
