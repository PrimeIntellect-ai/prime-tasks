Undefined error for macro example
## Versions

* Elixir: `Elixir 1.15.4 (compiled with Erlang/OTP 26)`
* Styler: `0.8.4 (styler) 4525686e`

## Example Input

```elixir
defmodule ListAssertions do
  defmacro assert_unordered(patterns, expression) when is_list(patterns) do
    clauses =
      patterns
      |> Enum.with_index()
      |> Enum.flat_map(fn {pattern, index} ->
        quote do
          unquote(pattern) -> unquote(index)
        end
      end)

    clauses =
      clauses ++
        quote do
          _ -> :not_found
        end

    quote do
      ListAssertions.__assert_unordered__(
        unquote(Macro.escape(patterns)),
        unquote(expression),
        fn x -> case x, do: unquote(clauses) end
      )
    end
  end

  def __assert_unordered__(patterns, enum, fun) do
    result =
      Enum.reduce(enum, %{}, fn item, acc ->
        case fun.(item) do
          :not_found ->
            raise ArgumentError,
                  "#{inspect(item)} does not match any pattern: #{Macro.to_string(patterns)}"

          index when is_map_key(acc, index) ->
            raise ArgumentError,
                  "both #{inspect(item)} and #{inspect(acc[index])} match pattern: " <>
                    Macro.to_string(Enum.fetch!(patterns, index))

          index when is_integer(index) ->
            Map.put(acc, index, item)
        end
      end)

    if map_size(result) == length(patterns) do
      :ok
    else
      raise ArgumentError,
            "expected enumerable to have #{length(patterns)} entries, got: #{map_size(result)}"
    end
  end
end

ExUnit.start()

defmodule ListAssertionsTest do
  use ExUnit.Case, async: true

  import ListAssertions

  test "all match" do
    assert_unordered([:foo, :bar, :baz], [:foo, :baz, :bar])
    assert_unordered([{:ok, _}, {:error, _}], [{:error, :bad}, {:ok, :good}])
  end

  test "duplicates" do
    assert_unordered([{:ok, _}, {:error, _}], [{:error, :bad}, {:ok, :good}, {:ok, :bad}])
  end

  test "too few" do
    assert_unordered([{:ok, _}, {:error, _}], [{:error, :bad}])
  end

  test "unknown" do
    assert_unordered([{:ok, _}, {:error, _}], [:what])
  end
end
```

Source from José: https://elixirforum.com/t/assert-a-list-of-patterns-ignoring-order/46068/8

## Stacktrace / Current Behaviour


The problem line is the third argument to `ListAssertions.__assert_unordered__` in the block above:

```
fn x -> case x, do: unquote(clauses) end
```


```
** (Protocol.UndefinedError) protocol Enumerable not implemented for {:unquote, [closing: [line: 120], line: 120], [{:clauses, [line: 120], nil}]} of type Tuple

    (elixir 1.15.4) lib/enum.ex:1: Enumerable.impl_for!/1
    (elixir 1.15.4) lib/enum.ex:166: Enumerable.reduce/3
    (elixir 1.15.4) lib/enum.ex:4387: Enum.map/2
    (styler 0.8.4) lib/style/single_node.ex:144: Styler.Style.SingleNode.style/1
    (styler 0.8.4) lib/style/single_node.ex:29: Styler.Style.SingleNode.run/2
    (styler 0.8.4) lib/zipper.ex:345: Styler.Zipper.do_traverse_while/3
    (styler 0.8.4) lib/styler.ex:36: anonymous fn/4 in Styler.style/3
    (elixir 1.15.4) lib/enum.ex:2510: Enum."-reduce/3-lists^foldl/2-0-"/3

Skipping style and continuing on
```
