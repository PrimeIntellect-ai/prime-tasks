Trace context propagation support in client
ClickHouse accepts trace context HTTP headers, as described by the [W3C recommendation](https://www.w3.org/TR/trace-context). It also accepts trace context over a native protocol that is used for communication between ClickHouse servers or between the client and server.
 Is there any plans to support sending trace trace to Clickhouse for query tracing?

### Additional contract requirements

For queries sent through the HTTP client, a valid OpenTelemetry span carried by the query context must be propagated in outgoing HTTP headers so ClickHouse can use it for query tracing. The propagated trace context must follow the W3C Trace Context format when the corresponding propagator is configured. This request covers HTTP requests, not the native protocol.
