Intermittent runtime error thrown in Elixir 1.17 / OTP 27
Hi,

I'm experiencing a runtime error being thrown when using Mimic.

The issue has been reproduced in the [navinpeiris/mimic-elixir-1.17-issue](https://github.com/navinpeiris/mimic-elixir-1.17-issue) repo.

You might need to run `mix test` a few times to reproduce the issue. If not, please let me know and I'll try my best to get version that causes the error.

I initially raised the issue in the Elixir repo: [elixir/issues/13662](https://github.com/elixir-lang/elixir/issues/13662).

### Elixir/OTP version

```
Erlang/OTP 27 [erts-15.0] [source] [64-bit] [smp:16:16] [ds:16:16:10] [async-threads:1]

Elixir 1.17.0 (compiled with Erlang/OTP 27)
```

### OS

```
MacOS Sonoma 14.5 (Intel)
```

### The error

```
** (EXIT from #PID<0.94.0>) an exception was raised:
    ** (RuntimeError) found error while checking types for HelloWorldTest."test test today 353"/1:

** (Protocol.UndefinedError) protocol Enumerable not implemented for nil of type Atom. This protocol is implemented for the following type(s): Date.Range, File.Stream, Function, GenEvent.Stream, HashDict, HashSet, IO.Stream, Jason.OrderedObject, List, Map, MapSet, Range, Stream
The exception happened while checking this code:

def test test today 353(_) do
  (
    Mimic.expect(Date, :utc_today, 10, fn ->
      %Date{calendar: Calendar.ISO, year: 2024, month: 3, day: 1}
    end)

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 10],
           [
             {:==, [line: 10],
              [
                {{:., [line: 10], [{:__aliases__, [line: 10], [:Date]}, :utc_today]}, [line: 10],
                 []},
                {:sigil_D, [line: 10], [{:<<>>, [line: 10], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 11],
           [
             {:==, [line: 11],
              [
                {{:., [line: 11], [{:__aliases__, [line: 11], [:Date]}, :utc_today]}, [line: 11],
                 []},
                {:sigil_D, [line: 11], [{:<<>>, [line: 11], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 12],
           [
             {:==, [line: 12],
              [
                {{:., [line: 12], [{:__aliases__, [line: 12], [:Date]}, :utc_today]}, [line: 12],
                 []},
                {:sigil_D, [line: 12], [{:<<>>, [line: 12], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 13],
           [
             {:==, [line: 13],
              [
                {{:., [line: 13], [{:__aliases__, [line: 13], [:Date]}, :utc_today]}, [line: 13],
                 []},
                {:sigil_D, [line: 13], [{:<<>>, [line: 13], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 14],
           [
             {:==, [line: 14],
              [
                {{:., [line: 14], [{:__aliases__, [line: 14], [:Date]}, :utc_today]}, [line: 14],
                 []},
                {:sigil_D, [line: 14], [{:<<>>, [line: 14], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 16],
           [
             {:==, [line: 16],
              [
                {{:., [line: 16], [{:__aliases__, [line: 16], [:Date]}, :utc_today]}, [line: 16],
                 []},
                {:sigil_D, [line: 16], [{:<<>>, [line: 16], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 17],
           [
             {:==, [line: 17],
              [
                {{:., [line: 17], [{:__aliases__, [line: 17], [:Date]}, :utc_today]}, [line: 17],
                 []},
                {:sigil_D, [line: 17], [{:<<>>, [line: 17], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 18],
           [
             {:==, [line: 18],
              [
                {{:., [line: 18], [{:__aliases__, [line: 18], [:Date]}, :utc_today]}, [line: 18],
                 []},
                {:sigil_D, [line: 18], [{:<<>>, [line: 18], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 19],
           [
             {:==, [line: 19],
              [
                {{:., [line: 19], [{:__aliases__, [line: 19], [:Date]}, :utc_today]}, [line: 19],
                 []},
                {:sigil_D, [line: 19], [{:<<>>, [line: 19], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )

    (
      left = Date.utc_today()
      right = %{__struct__: Date, calendar: Calendar.ISO, year: 2024, month: 3, day: 1}

      ExUnit.Assertions.assert(:erlang.==(left, right),
        left: left,
        right: right,
        expr:
          {:assert, [line: 20],
           [
             {:==, [line: 20],
              [
                {{:., [line: 20], [{:__aliases__, [line: 20], [:Date]}, :utc_today]}, [line: 20],
                 []},
                {:sigil_D, [line: 20], [{:<<>>, [line: 20], ["2024-03-01"]}, []]}
              ]}
           ]},
        message: "Assertion with == failed",
        context: :==
      )
    )
  )

  :ok
end

Please report this bug at: https://github.com/elixir-lang/elixir/issues

        (elixir 1.17.0) lib/enum.ex:1: Enumerable.impl_for!/1
        (elixir 1.17.0) lib/enum.ex:166: Enumerable.reduce/3
        (elixir 1.17.0) lib/enum.ex:4423: Enum.reduce/3
        (elixir 1.17.0) lib/module/types/of.ex:182: Module.Types.Of.struct/6
        (elixir 1.17.0) lib/module/types/expr.ex:503: anonymous fn/3 in Module.Types.Expr.of_clauses/3
        (elixir 1.17.0) lib/module/types/helpers.ex:108: Module.Types.Helpers.do_reduce_ok/3
        (elixir 1.17.0) lib/module/types/expr.ex:219: Module.Types.Expr.of_expr/3
        (elixir 1.17.0) lib/module/types/helpers.ex:128: Module.Types.Helpers.do_map_reduce_ok/3
        (elixir 1.17.0) lib/module/types/expr.ex:332: Module.Types.Expr.of_expr/3
        (elixir 1.17.0) lib/module/types/helpers.ex:128: Module.Types.Helpers.do_map_reduce_ok/3
        (elixir 1.17.0) lib/module/types/expr.ex:185: Module.Types.Expr.of_expr/3
        (elixir 1.17.0) lib/module/types/helpers.ex:128: Module.Types.Helpers.do_map_reduce_ok/3
        (elixir 1.17.0) lib/module/types/expr.ex:185: Module.Types.Expr.of_expr/3
        (elixir 1.17.0) lib/module/types.ex:56: Module.Types.warnings_from_clause/6
        (elixir 1.17.0) lib/module/types.ex:15: anonymous fn/7 in Module.Types.warnings/5
        (elixir 1.17.0) lib/enum.ex:4353: Enum.flat_map_list/2
        (elixir 1.17.0) lib/enum.ex:4354: Enum.flat_map_list/2
        (elixir 1.17.0) lib/module/parallel_checker.ex:264: Module.ParallelChecker.check_module/3
        (elixir 1.17.0) lib/module/parallel_checker.ex:82: anonymous fn/6 in Module.ParallelChecker.spawn/4

mix test  15.72s user 1.49s system 111% cpu 15.446 total
```
