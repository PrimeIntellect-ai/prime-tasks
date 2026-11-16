Formatter Plugin crashing with Elixir 1.13.0
## Versions

* Elixir: `1.13.0`
* Erlang: `24.1.6`
* surface: `0.6.1`
* surface_formatter: `0.7.1`

## Error

```
mix format failed for file: lib/hygeia_web/live/statistics_live/export.sface
** (FunctionClauseError) no function clause matching in Inspect.Algebra.format/2

    The following arguments were given to Inspect.Algebra.format/2:

        # 1
        {:doc_group, {:doc_cons, {:doc_string, "gettext", 7}, {:doc_group, {:doc_cons, {:doc_cons, {:doc_cons, {:doc_nest, {:doc_cons, "(", {:doc_break, "", :strict}}, 2, :break}, {:doc_cons, {:doc_nest, {:doc_cons, {:doc_cons, "\"", {:doc_string, "From", 4}}, "\""}, 2, :break}, {:doc_break, "", :strict}}}, ")"}, :doc_nil}, :self}}, :self}

        # 2
        nil

    Attempted function clauses (showing 1 out of 1):

        def format(doc, width) when is_binary(doc) or doc === :doc_nil or doc === :doc_line or is_tuple(doc) and elem(doc, 0) === :doc_break or elem(doc, 0) === :doc_collapse or elem(doc, 0) === :doc_color or elem(doc, 0) === :doc_cons or elem(doc, 0) === :doc_fits or elem(doc, 0) === :doc_force or elem(doc, 0) === :doc_group or elem(doc, 0) === :doc_nest or elem(doc, 0) === :doc_string and width == :infinity or is_integer(width) and width >= 0

    (elixir 1.13.0) lib/inspect/algebra.ex:958: Inspect.Algebra.format/2
    lib/surface/formatter/phases/render.ex:38: Surface.Formatter.Phases.Render.render_node/2
    (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
    lib/surface/formatter/phases/render.ex:183: Surface.Formatter.Phases.Render.render_node/2
    (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
    (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
    lib/surface/formatter/phases/render.ex:183: Surface.Formatter.Phases.Render.render_node/2
    (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
```

See in CI: https://github.com/jshmrtn/hygeia/runs/4412768200?check_suite_focus=true

## Config

```
[
  import_deps: [:phoenix, :phoenix_live_view, :surface, :ecto, :ecto_enum],
  inputs: [
    ".dialyzer_ignore.exs",
    ".formatter.exs",
    "*.{ex,exs}",
    "priv/*/seeds.exs",
    "priv/repo/seeds/*.exs",
    "{config,lib,test}/**/*.{ex,exs,sface}"
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Surface.Formatter.Plugin]
]
```
