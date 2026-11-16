Support SignalEntity API
This allows orchestrations to send messages to Entities without needing to `yield` / `await` on an API. The implementation should be similar to `ContinueAsNew`, which is also a fire-and-forget operation.

### Additional contract requirements

The orchestration context exposes `signalEntity(entityId, operationName, operationInput?)` to target an Entity with the named operation and optional input. Calling it schedules a fire-and-forget signal; orchestration code does not need to yield or await the call.
