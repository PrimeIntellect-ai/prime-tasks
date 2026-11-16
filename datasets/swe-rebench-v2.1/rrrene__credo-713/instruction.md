PipeChainStart with :atom excluded fails on nil
The following code:
```elixir
foo(nil) |> bar()
```

will fail the `PipeChainStart` test even when `excluded_argument_types: [:atom]` is set. [HIDDEN]

Fixed in https://github.com/rrrene/credo/pull/713

### Additional contract requirements

- When `excluded_argument_types` includes `:atom`, a pipe chain starting with a call whose first argument is an atom, including `nil`, must not be reported as a violation.
