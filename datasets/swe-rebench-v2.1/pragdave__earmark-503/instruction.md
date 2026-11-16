Earmark crashes (like EarmarkParser) on `"\\[{:}" `
https://github.com/RobertDober/earmark_parser/issues/154

here is the crash in Earmark master

```
Generated earmark app
Interactive Elixir (1.17.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> EarmarkParser.as_ast("\\[{:}")
** (UndefinedFunctionError) function EarmarkParser.as_ast/1 is undefined (module EarmarkParser is not available)
    EarmarkParser.as_ast("\\[{:}")
    iex:1: (file)
iex(1)> Earmark.as_ast("\\[{:}")
** (FunctionClauseError) no function clause matching [HIDDEN]

    The following arguments were given to Earmark.Parser.Helpers.AstHelpers.augment_tag_with_ial/2:

        # 1
        ["["]

        # 2
        %{}

    Attempted function clauses (showing 2 out of 2):

        def [HIDDEN]

    (earmark 1.4.46) lib/earmark_parser/helpers/ast_helpers.ex[HIDDEN]
    (earmark 1.4.46) lib/earmark_parser/ast/inline.ex:258: [HIDDEN]
    (elixir 1.17.1) lib/enum.ex:4343: [HIDDEN]
    (earmark 1.4.46) lib/earmark_parser/ast/inline.ex:36: [HIDDEN]
    (earmark 1.4.46) lib/earmark_parser/ast_renderer.ex:32: Earmark.Parser.AstRenderer.render_block/3
    (earmark 1.4.46) lib/earmark_parser/ast_renderer.ex:23: Earmark.Parser.AstRenderer._render/3
    (earmark 1.4.46) lib/earmark_parser.ex:594: Earmark.Parser.as_ast/2
    iex:1: (file)
```

@amit-chaudhari1 if ok with you I (ab)use me right to assign it to myself as the liklhood that I can backport the fix is high

### Additional contract requirements

- When called as `Earmark.as_html("\\[{:}")`, the result must be `{:ok, "<p>\n[{:}</p>\n", []}`.
- When called as `Earmark.as_ast("\\[{:}")`, it must not raise and must return `{:ok, ast, messages}`.
