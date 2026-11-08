+2 ABCSize for each `@impl SomeModule` inside quote block
### Environment

* Credo version (`mix credo -v`):
```
$ mix credo -v
1.7.10-ref.(HEAD odłączone na origin/master).2e15cdd2
```
* Erlang/Elixir version (`elixir -v`):
```
$ elixir -v
Erlang/OTP 27 [erts-15.2] [source] [64-bit] [smp:32:32] [ds:32:32:10] [async-threads:1] [jit:ns]

Elixir 1.18.0-rc.0 (f00f759) (compiled with Erlang/OTP 27)
```
* Operating system:
> Gentoo Linux using `desktop/plasma` profile for version `23.0` and with kernel version `6.6.58`.

### What were you trying to do?

I have found that size of `@impl SomeModule` is different inside `quote do … end` block. In result in 2 of my macros by simply commenting out all `@impl` lines changes the `credo` result from fail to pass. It's giving +2 size for each such line which is really a lot having in mind the default limit is 30. Think that just 2 **same** lines makes more than 10% check size.

### Expected outcome

In "normal" case it have `0.0` result, so if we use it as a starting point it should be as same within `quote` block or at least it should be more realistic (not more than 1 per line I guess) + don't increment with 2 or more same lines. Of course nowhere in code I have so many `@impl`, but I have noticed that those are increasing size way too much.

### Actual outcome

```elixir
source1 = """
@impl SomeModule
"""

{:ok, ast1} = Credo.Code.ast(source1)
Credo.Check.Refactor.ABCSize.abc_size_for(ast1, [])
0

source2 = """
def sample do
  quote do
    @impl SomeModule
  end
end
"""

{:ok, ast2} = Credo.Code.ast(source2)
Credo.Check.Refactor.ABCSize.abc_size_for(ast2, [])
3.0

source3 = """
def sample do
  quote do
    @impl SomeModule
    @impl SomeModule
  end
end
"""

{:ok, ast3} = Credo.Code.ast(source3)
Credo.Check.Refactor.ABCSize.abc_size_for(ast3, [])
5.0

many_impls = "@impl SomeModule" |> List.duplicate(30) |> Enum.join("\n    ")

source4 = """
def sample do
  quote do
    #{many_impls}
  end
end
"""

{:ok, ast4} = Credo.Code.ast(source4)
Credo.Check.Refactor.ABCSize.abc_size_for(ast4, [])
61.0
```

**Edit**: People with same problem can temporary workaround it by setting `[excluded_functions: ["@"]]` as check options.

### Additional contract requirements

Within a `quote` block, each `@impl SomeModule` occurrence contributes exactly one ABC assignment point. Repeating identical `@impl SomeModule` lines contributes one point for each occurrence, not two or more points per line.
