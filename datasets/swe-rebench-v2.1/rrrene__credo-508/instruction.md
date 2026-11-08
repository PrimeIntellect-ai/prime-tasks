`mix credo` task fails with exception `protocol String.Chars not implemented for ...`
### Environment

* Credo version (`mix credo -v`): 0.8.10
* Erlang/Elixir version (`elixir -v`): 1.6.1
* Operating system: macOS 10.13.3

### What were you trying to do?

I'm trying to run style checks for source code containing macro like

```
defmacro foo(quoted_module, ..., ...) do
  {module, []} = Code.eval_quoted(quoted_module)
  quote do
    defmodule unquote(module).Bar do
      unquote(...)
    end
  end
end
```

Compiler gives no warnings, generated module works as expected. But when I'm trying to run style checks with `mix credo` command, it fails with error

```
Error while running Elixir.Credo.Check.Readability.ModuleNames on
** (EXIT from #PID<0.73.0>) an exception was raised:
    ** (Protocol.UndefinedError) protocol String.Chars not implemented for {:unquote, [line: 22], [{:module, [line: 22], nil}]}
        (elixir) lib/string/chars.ex:3: String.Chars.impl_for!/1
        (elixir) lib/string/chars.ex:22: String.Chars.to_string/1
        (elixir) lib/enum.ex:1899: Enum."-join/2-lists^foldl/2-0-"/3
        (elixir) lib/enum.ex:1899: Enum.join/2
        lib/credo/check/readability/module_names.ex:45: Credo.Check.Readability.ModuleNames.issues_for_def/3
        lib/credo/check/readability/module_names.ex:36: Credo.Check.Readability.ModuleNames.traverse/3
        (elixir) lib/macro.ex:277: anonymous fn/4 in Macro.do_traverse_args/4
        (elixir) lib/enum.ex:1397: Enum."-map_reduce/3-lists^mapfoldl/2-0-"/3
```

### Additional contract requirements

- When a module name cannot be determined, `Credo.Check.Readability.ModuleNames` must not report an issue for it.
