Logging and tracing correlation
Add support for logging a trace id through Helidon MDC. This can be a separate module, or just update to existing tracing implementation, where we would add the top level span traceId to Helidon Logging MDC. Then users could use one of our logging integration modules to log the trace id with every single log statement.

This feature is important for correlation of traces and log statements (such as when using Verrazzano)

### Additional contract requirements

- The top-level span's trace ID must be available through Helidon MDC under the key `trace_id`.
- A Helidon logging integration configured to include the `trace_id` MDC value must emit the active trace ID in log statements while a span is active.
