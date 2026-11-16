Adding a prefix to the aggregate in the router breaks the strong consistency of the router
When you add a prefix to an AggregateRoot in the Router:

```elixir
  defmodule ConsistencyRouter do
    use Commanded.Commands.Router

    identify ConsistencyAggregateRoot,
        by: :uuid,
        prefix: "some-prefix"

    dispatch [ConsistencyCommand,NoOpCommand,RequestDispatchCommand],
      to: ConsistencyAggregateRoot
  end
```

and then try to use `Router.dispatch(..., consistency: :strong)` it never returns `:ok`, but always `{:error, :consistency_timeout}`. You can easily test this in the `dispatch_consistency_test.exs`

### Additional contract requirements

- When dispatching with `include_execution_result: true`, `ExecutionResult.aggregate_uuid` must include the configured identity prefix; with the test prefix, it must equal `"example-prefix-" <> uuid`.
- `Commanded.Aggregates.Supervisor.open_aggregate(aggregate_module, aggregate_uuid)` starts (or locates) the aggregate process for the given aggregate module and UUID, and returns `{:ok, aggregate_uuid}`. The full aggregate UUID, including any required prefix, must be supplied directly as `aggregate_uuid`.
