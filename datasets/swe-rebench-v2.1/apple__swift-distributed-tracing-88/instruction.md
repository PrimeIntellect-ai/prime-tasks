Allow mutation of span operation name
We might want to consider offering an API to rename an already started span. This is [part of the OTel spec](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/api.md#updatename) but comes with a disadvantage for sampling.

### Use-Case: HTTP Server

HTTP servers might want to rename a span after creation, because they can come up with a more relevant span in the meantime.

1. Immediately start span when receiving a request (`operationName` = `request.head.uri`)
2. Route request
  2.1. Route Not Found --> Record error
  2.2 Route Found --> Rename to route (`/users/1` becomes `/users/:userID`)
3. End span

This approach has one disadvantage. In a typical tracer with head-first sampling, sampling decisions based on the `operationName` of a span will potentially not be accurate as the sampler won't be invoked after the rename.

### Alternatives: Start spans after the fact

As mentioned in [OTel Spec: `Span.UpdateName`](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/api.md#updatename) an alternative to renaming an already started span would be to record the timestamp whenever the span should have been started, and then passing that timestamp to the `startSpan` call.

1. Get current timestamp
2. Route request
  2.1. Route Not Found --> Start span at previous timestamp (`operationName` = `request.head.uri`) --> Record error
  2.2 Route Found --> Start span at previous timestamp (`operationName` = `/users/:userID`)
3. End span

### Additional contract requirements

- The `Span` protocol in module `Tracing` exposes a mutable `operationName` property of type `String`. Reading it returns the span's current operation name, and assigning to it updates the stored name. An implementation may ignore an assignment (for example, a no-op span may keep returning the name it was created with).
- `NoOpTracer.NoOpSpan` in module `Tracing` provides a public initializer `init(operationName: String, baggage: Baggage)` that accepts the operation name and baggage. The span returns the supplied operation name from its `operationName` property.
