NegatedIsNil check can consume all available memory
### Precheck

* Proposals for new features should be submitted via: https://github.com/rrrene/credo-proposals
* For bugs, please do a quick search and make sure the bug has not yet been reported here

### Environment

* Credo version (`mix credo -v`): 1.7.0
* Erlang/Elixir version (`elixir -v`): 1.14.2
* Operating system: Any

### What were you trying to do?

When using the `NegatedIsNil` check and a file has a violation, the ast traversal is mishandling the issues list and will concatenate the list with itself for every other function with a non violating guard in the file after the violation is found.
The results will range from reporting the same line multiple times up to consuming all available memory until it's killed, depending on the number of functions with guards that come after a violating function in a file.

A benign example:

```elixir
defmodule Credobomb do
  def hello(a) when not is_nil(a), do: a

  def foo1(x) when is_integer(x), do: x

  def foo2(x) when is_integer(x), do: x
end
```

```
mix credo --strict
Checking 3 source files ...

  Refactoring opportunities
┃
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:2 #(Credobomb.hello)
```

The issues list ends up containing 3^n entries where n = the number of guarded functions after a violating function. Multiple violating functions will increase this. A further illustration can be seen by reordering the functions in the file:

```elixir
defmodule Credobomb do
  def foo1(x) when is_integer(x), do: x

  def foo2(x) when is_integer(x), do: x

  def hello(a) when not is_nil(a), do: a
end
```

```
mix credo --strict
Checking 3 source files ...

  Refactoring opportunities
┃
┃ [F] ↘ Negated is_nil in guard clause found
┃       lib/credobomb.ex:6 #(Credobomb.hello)
```
