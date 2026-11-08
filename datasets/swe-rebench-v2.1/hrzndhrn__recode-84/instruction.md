Failing on __MODULE__ aliases with `as`
Hi! Thank you for this tool. I am trying to test it but it fails for me for __MODULE__ aliases

```elixir
alias __MODULE__, as: SummaryForm
```

It fails with:

```
** (FunctionClauseError) no function clause matching in Recode.AST.alias_info/1

    The following arguments were given to Recode.AST.alias_info/1:

        # 1
        {:alias, [trailing_comments: [], leading_comments: [], end_of_expression: [newlines: 1, line: 6, column: 36], line: 6, column: 3], [{:__MODULE__, [trailing_comments: [], leading_comments: [], line: 6, column: 9], nil}, [{{:__block__, [trailing_comments: [], leading_comments: [], format: :keyword, line: 6, column: 21], [:as]}, {:__aliases__, [trailing_comments: [], leading_comments: [], last: [line: 6, column: 25], line: 6, column: 25], [:SummaryForm]}}]]}

    Attempted function clauses (showing 8 out of 8):

        def alias_info({:alias, _meta1, [{:__aliases__, _meta2, aliases}]})
        def alias_info({:alias, _meta1, [{:__MODULE__, _meta2, nil}]})
        def alias_info({:alias, _meta1, [{{:., _meta2, [{:__MODULE__, _meta3, _args}, _opts]}, _meta4, multi}]})
        def alias_info({:alias, _meta1, [{{:., _meta2, [aliases, _opts]}, _meta3, multi}]})
        def alias_info({:alias, _meta1, [{:__aliases__, _meta2, aliases}, [{_block, as}]]})
        def alias_info({:alias, _meta1, [{:__block__, _meta2, aliases}, [{_block, as}]]})
        def alias_info({:alias, _meta1, [{:unquote, _meta2, _args}]})
        def alias_info({:alias, _meta1, [{:unquote, _meta2, _args}, [{_block, as}]]})
```
