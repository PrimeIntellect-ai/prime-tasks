Regressions in 0.9
It appears the changes from JSX -> Jason left some inconsistencies with source stats being both in keyword lists and in maps. This ends up raising `FunctionClauseErrors` when the keyword list is pattern matched:

```elixir
** (FunctionClauseError) no function clause matching in anonymous fn/1 in ExCoveralls.Stats.append_sub_app_name/3

    The following arguments were given to anonymous fn/1 in ExCoveralls.Stats.append_sub_app_name/3:

        # 1
        %{coverage: [nil, nil, nil, nil...
```

PR #141 submitted as fix.
