Warn on phx.gen.live if LiveView.JS is missing?
<!--
### Precheck

* For general discussions and support, use Stack Overflow or the Elixir Forum
* For proposing and discussing new features, start a thread on the Phoenix Core mailing list
* For bugs, do a quick search and make sure the bug has not yet been reported
* Ensure that this issue is related to the Phoenix library and not one of the dependencies listed in mix.exs (Ecto, Plug, etc.)
* All checked? Be nice and have fun!
-->

The latest generator relies on `Phoenix.LiveView.JS` which requires LiveView v0.17+. Without the module, running `mix phx.server` after running the generator will emit a compilation error:

```sh
== Compilation error in file lib/fiddle_web/live/live_helpers.ex ==
** (CompileError) lib/fiddle_web/live/live_helpers.ex:55: Phoenix.LiveView.JS.__struct__/1 is undefined, cannot expand struct Phoenix.LiveView.JS. Make sure the struct name is correct. If the struct name exists and is correct but it still cannot be found, you likely have cyclic module usage in your code
    lib/fiddle_web/live/live_helpers.ex:55: (module)
```

Should we check whether or not `LiveView.JS` is loaded and print a warning for the user to upgrade? They will need to update deps for LiveView and LiveDashboard:

```elixir
defp deps do
 [
    {:phoenix_live_view, "~> 0.17"},
    {:phoenix_live_dashboard", "~> 0.6"}
    # deps...
  ]
end
```

### Additional contract requirements

- When `Phoenix.LiveView.JS` is missing, emit a Mix shell `:info` message with exactly this value: `"\nYou must update :phoenix_live_view to v0.17 or later and\n:phoenix_live_dashboard to v0.6 or later to use the features\nin this generator.\n"`.
- When `Phoenix.LiveView.JS` is available, do not emit that upgrade message.
