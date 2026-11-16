Additional stream prefix per aggregate
It would be useful to be able to define a prefix on a per-aggregate basis. This would reduce risk of collisions when using a lot of aggregates with generated IDs and ease separation of streams on a business logic level.

# Example

Let's assume we have a general User aggregate which uses UUIDs as identification. For our business logic we need to relate additional data to this user, as such we add additional aggregates which also use the user ids as identification for ease of use. While being related but separate entities this would result in a single stream containing all events from all aggregates per user.

# Proposal

Similar to process managers or event handlers the name of an aggregate could be defined in a use clause. This could internally define a `@behaviour` conformance with a callback providing the aggregate name.

To allow backwards compatibility the `Aggregate` module could use `function_exported?/3` to check for the behaviour conformance in advance and fall back to the current logic. The old behaviour could be deprecated if wished for and removed in a later version.

---

What do you think of this?

### Additional contract requirements

- `Commanded.Aggregates.Supervisor.open_aggregate(aggregate_module, aggregate_uuid, identity_prefix \\ nil)` starts, or locates an already running, aggregate process and returns `{:ok, aggregate_uuid}`. When an `identity_prefix` is supplied it is prepended to the aggregate's UUID to form the event-store stream used both when appending and when reading the aggregate's events.
- `Commanded.Aggregates.Aggregate.execute(aggregate_module, aggregate_uuid, context, timeout \\ 5_000)` executes a command against the aggregate identified by both its module and its UUID.
- `Commanded.Aggregates.Aggregate.aggregate_state(aggregate_module, aggregate_uuid)` returns the aggregate's current state.
- `Commanded.Aggregates.Aggregate.aggregate_version(aggregate_module, aggregate_uuid)` returns the aggregate's current version.
- The aggregate process is registered under the key `{aggregate_module, aggregate_uuid}` in the aggregate registry.
- `Commanded.Commands.Router.identify(aggregate_module, opts)` declares the identity used for all commands targeting an aggregate. `opts` accepts `:by`, which is either a command field name (an atom) or an arity-1 function returning the identity from the command, and an optional `:prefix` string that is prepended to the identity when forming the event-store stream.
- A command registration may include an `identity_prefix` option. This option is supplied when registering the command, not as an option on an individual `dispatch` call, and is prepended to the aggregate identity when forming the event-store stream.
- `Commanded.Helpers.Process.shutdown(aggregate_module, aggregate_uuid)` stops the aggregate process identified by both its module and its UUID.
- If `dispatch` receives the unexpected parameter `id`, it raises a `RuntimeError` with this exact message, including the final newline:

```text
unexpected dispatch parameter "id"
available params are: to, function, aggregate, identity, identity_prefix, timeout, lifespan, consistency
```
