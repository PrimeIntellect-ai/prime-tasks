Macro expansion goes too far and/or Ecto does not understand orelse/andalso
### Environment

* Elixir version (elixir -v):
  ```zsh
  Erlang/OTP 20 [erts-9.0] [source] [64-bit] [smp:2:2] [ds:2:2:10] [async-threads:10] [hipe] [kernel-poll:false]

  Elixir 1.6.0-dev (0beeef8) (compiled with OTP 20)
  ```
* Database and version (PostgreSQL 9.4, MongoDB 3.2, etc.):  PostgreSQL 9.7
* Ecto version (mix deps):  ecto 2.2.1
* Database adapter and version (mix deps):  postgrex 0.13.3
* Operating system:  Linux 3.10.0-514.26.2.el7.x86_64 #1 SMP Fri Jun 30 05:26:04 UTC 2017 x86_64 x86_64 x86_64 GNU/Linux

### Current behavior

Given a simple macro like:
```elixir
  defmacrop status_active(var) do
    quote do
      unquote(var) != "I" or is_nil(unquote(var))
    end
  end
```
And trying to use it like:
```elixir
          join(query, qual, [spriden],
            goremal in DB.Banner.GOREMAL,
            goremal.goremal_pidm == spriden.spriden_pidm and status_active(goremal.goremal_status_ind)
          )
```
Causes this error:
```elixir
== Compilation error in file lib/my_server/banner.ex ==
** (Ecto.Query.CompileError) `:erlang.orelse(goremal.goremal_status_ind() <> "I", is_nil(goremal.goremal_status_ind()))` is not a valid query expression
    expanding macro: Ecto.Query.join/5
    lib/my_server/banner.ex:108: MyServer.Banner.query_fullprofile/2
    (elixir) lib/kernel/parallel_compiler.ex:121: anonymous fn/4 in Kernel.ParallelCompiler.spawn_compilers/1
```
I've tried various things including building the AST manually:
```elixir
  defmacrop status_active(var) do
    {:or, [],
     [{:!=, [], [var, "I"]},
      {:is_nil, [], [var]}]}
  end
```
Not bringing in the kernel import:
```elixir
  defmacrop status_active(var) do
    import Kernel, except: [or: 2]
    quote do
      unquote(var) != "I" or is_nil(unquote(var))
    end
  end
```
As well as inside the macro:
```elixir
  defmacrop status_active(var) do
    quote do
      import Kernel, except: [or: 2]
      unquote(var) != "I" or is_nil(unquote(var))
    end
  end
```
The last example of which gives a different error of:
```elixir
== Compilation error in file lib/my_server/banner.ex ==
** (Ecto.Query.CompileError) `(
  import(Kernel, except: [or: 2])
  goremal.goremal_status_ind() != "I" or is_nil(goremal.goremal_status_ind())
)` is not a valid query expression.

* If you intended to call a database function, please check the documentation
  for Ecto.Query to see the supported database expressions

* If you intended to call an Elixir function or introduce a value,
  you need to explicitly interpolate it with ^

    expanding macro: Ecto.Query.join/5
    lib/my_server/banner.ex:108: MyServer.Banner.query_fullprofile/2
    (elixir) lib/kernel/parallel_compiler.ex:121: anonymous fn/4 in Kernel.ParallelCompiler.spawn_compilers/1
```

### Expected behavior

[HIDDEN]

Current workaround is to put it in a fragment, but then I lose the ability to make sure some casts are done right in some cases without also introducing in extra arguments, thus cluttering the API (the example above is a simplified example).

### Additional contract requirements

- Macro-generated logical predicates used in queries must be accepted as query expressions and translated into SQL.
- Logical `or` and `and` operators in macro-generated predicates must translate to SQL `OR` and `AND`, respectively, including when the predicate is produced through nested macro expansion.
