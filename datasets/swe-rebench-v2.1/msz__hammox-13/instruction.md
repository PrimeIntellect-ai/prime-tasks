Exception thrown with Decimal.t
Could you please tell me if `hammox` has support for custom types? For example:

```elixir
defmodule MyType do
  defstruct [:value]

  @type t :: %__MODULE__{
    value: number()
   }
end
```

Looking through the source code and the following error, I am assuming it doesn't currently:

```
     The following arguments were given to Hammox.TypeEngine.match_type/2:

         # 1
         1000

         # 2
         {:op, 93, :-, {:integer, 93, 1}}

     Attempted function clauses (showing 10 out of 89):

         def match_type(value, {:type, _, :union, union_types} = union) when is_list(union_types)
         def match_type(_value, {:type, _, :any, []})
         def match_type(value, {:type, _, :none, []} = type)
         def match_type(value, {:type, _, :atom, []}) when is_atom(value)
         def match_type(value, {:type, _, :atom, []} = type)
         def match_type(value, {:type, _, :map, :any}) when is_map(value)
         def match_type(value, {:type, _, :pid, []}) when is_pid(value)
         def match_type(value, {:type, _, :pid, []} = type)
         def match_type(value, {:type, _, :port, []}) when is_port(value)
         def match_type(value, {:type, _, :port, []} = type)

     stacktrace:
       (hammox) lib/hammox/type_engine.ex:6: Hammox.TypeEngine.match_type/2
       (hammox) lib/hammox/type_engine.ex:9: anonymous fn/3 in Hammox.TypeEngine.match_type/2
       (elixir) lib/enum.ex:3325: Enumerable.List.reduce/3
       (elixir) lib/enum.ex:1998: Enum.reduce_while/3
       (hammox) lib/hammox/type_engine.ex:8: Hammox.TypeEngine.match_type/2
       (hammox) lib/hammox/type_engine.ex:364: anonymous fn/3 in Hammox.TypeEngine.match_type/2
       (elixir) lib/enum.ex:1340: anonymous fn/3 in Enum.map/2
       (stdlib) maps.erl:232: :maps.fold_1/3
       (elixir) lib/enum.ex:1964: Enum.map/2
       (hammox) lib/hammox/type_engine.ex:363: anonymous fn/2 in Hammox.TypeEngine.match_type/2
       (elixir) lib/enum.ex:3358: Enumerable.Map.reduce_list/3
       (elixir) lib/enum.ex:1998: Enum.reduce_while/3
       (hammox) lib/hammox/type_engine.ex:361: Hammox.TypeEngine.match_type/2
       (hammox) lib/hammox/type_engine.ex:364: anonymous fn/3 in Hammox.TypeEngine.match_type/2
       (elixir) lib/enum.ex:1340: anonymous fn/3 in Enum.map/2
       (stdlib) maps.erl:232: :maps.fold_1/3
       (elixir) lib/enum.ex:1964: Enum.map/2
       (hammox) lib/hammox/type_engine.ex:363: anonymous fn/2 in Hammox.TypeEngine.match_type/2
       (elixir) lib/enum.ex:3358: Enumerable.Map.reduce_list/3
       (elixir) lib/enum.ex:1998: Enum.reduce_while/3
```

Thank you for your help!

### Additional contract requirements

- When matching a negative integer literal type, Hammox must accept the matching integer and treat a nonmatching value as a type mismatch rather than raising a function-clause exception.
