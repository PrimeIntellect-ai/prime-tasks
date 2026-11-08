Hammox breaks when there is a @typep
[HIDDEN]

However, Typespecs accepts `@type`, `@typep` and `@opaque` ([source](https://hexdocs.pm/elixir/typespecs.html#user-defined-types)). This causes hammox to break:

```elixir
     ** (FunctionClauseError) no function clause matching in anonymous fn/1 in Hammox.TypeEngine.get_type/3

     The following arguments were given to anonymous fn/1 in Hammox.TypeEngine.get_type/3:

         # 1
         {:typep, {:names, {:remote_type, 133, [{:atom, 0, MapSet}, {:atom, 0, :t}, []]}, []}}

     stacktrace:
       (hammox 0.2.4) lib/hammox/type_engine.ex:695: anonymous fn/1 in Hammox.TypeEngine.get_type/3
       (elixir 1.10.2) lib/enum.ex:3305: Enum.find_list/3
       (hammox 0.2.4) lib/hammox/type_engine.ex:695: Hammox.TypeEngine.get_type/3
       (hammox 0.2.4) lib/hammox/type_engine.ex:656: Hammox.TypeEngine.resolve_remote_type/1
       (hammox 0.2.4) lib/hammox/type_engine.ex:621: Hammox.TypeEngine.match_type/2
       (hammox 0.2.4) lib/hammox.ex:312: Hammox.match_return_value/2
       (hammox 0.2.4) lib/hammox.ex:280: Hammox.match_call/3
       (hammox 0.2.4) lib/hammox.ex:264: anonymous fn/4 in Hammox.check_call/3
       (elixir 1.10.2) lib/enum.ex:3686: Enumerable.List.reduce/3
       (elixir 1.10.2) lib/enum.ex:2161: Enum.reduce_while/3
       (hammox 0.2.4) lib/hammox.ex:263: Hammox.check_call/3
       (hammox 0.2.4) lib/hammox.ex:256: Hammox.protected_code/3
```

In my case, I'm using `Ecto.Multi.t()` as the return value of a function, and this structure defines `@typep`: https://github.com/elixir-ecto/ecto/blob/v3.4.4/lib/ecto/multi.ex#L133

### Additional contract requirements

- Hammox must correctly match callback return values against user-defined types declared with `@type`, `@typep`, and `@opaque`, whether referenced directly or through aliases. These type declarations must not cause matching to crash; matching must accept values that conform to the declared type and reject values that do not.
