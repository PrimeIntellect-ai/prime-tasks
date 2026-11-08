FunctionClauseError in Surface.Formatter.Phases.Render.quoted_strings_with_newlines/1
The problem is new in `0.7.3`, it worked in `0.7.2`.

Update PR in our project: https://github.com/jshmrtn/hygeia/pull/1036
Failed CI (detailed error): https://github.com/jshmrtn/hygeia/runs/4584434083?check_suite_focus=true
File with Problems: https://github.com/jshmrtn/hygeia/blob/master/lib/hygeia_web/live/organisation_live/merge.sface

Detailed Error:

```
mix format --check-formatted
mix format failed for file: lib/hygeia_web/live/organisation_live/merge.sface
** (FunctionClauseError) no function clause matching in Surface.Formatter.Phases.Render.quoted_strings_with_newlines/1

    The following arguments were given to Surface.Formatter.Phases.Render.quoted_strings_with_newlines/1:

        # 1
        {:unless, [line: 1], [{:is_nil, [line: 1], [{:@, [line: 1], [{:delete, [line: 1], nil}]}]}, [do: {{:., [line: 1], [{:@, [line: 1], [{:delete, [line: 1], nil}]}, :uuid]}, [no_parens: true, line: 1], []}]]}

    Attempted function clauses (showing 2 out of 2):

        defp quoted_strings_with_newlines(+attribute_expression+) when -is_binary(attribute_expression)-
        defp quoted_strings_with_newlines(+nodes+) when -is_list(nodes)-

    lib/surface/formatter/phases/render.ex:377: Surface.Formatter.Phases.Render.quoted_strings_with_newlines/1
Warning:     lib/surface/formatter/phases/render.ex:445: Surface.Formatter.Phases.Render.format_attribute_expression/2
    lib/surface/formatter/phases/render.ex:371: Surface.Formatter.Phases.Render.render_attribute/2
Warning:     (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
    (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
Warning:     lib/surface/formatter/phases/render.ex:203: Surface.Formatter.Phases.Render.render_opening_tag/3
    (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
Warning:     (elixir 1.13.0) lib/enum.ex:1593: Enum."-map/2-lists^map/1-0-"/2
Error: Process completed with exit code 1.
```

### Additional contract requirements

- For each of the following inputs, formatting must leave the entire input byte-for-byte unchanged:

```surface
<Component
  id="foo"
  value={if @bar, do: "baz

  qux"}
/>
```

```surface
<Component
  id="foo"
  value={if @bar do
    if @baz do
      unless @qux do
        "result
        with
        newlines"
      end
    end
  end}
/>
```

```surface
<Component
  id="1"
  value={case @foo do
    "bar" ->
      with "qux" <- @baz,
           :ok <- value?() do
        cond do
          @test != "newliney
          " ->
            "pass"
        end
      end

    :baz ->
      nil
  end}
/>
```
