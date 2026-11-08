Send trace origin
See https://github.com/getsentry/team-sdks/issues/14 and the [trace origin docs](https://develop.sentry.dev/sdk/telemetry/traces/trace-origin/). This functionality is currently missing from the Rust SDK and should be added.

### Additional contract requirements

- Transactions created by the Rust SDK's automatic tracing instrumentation must include trace data with the key `origin` and the value `auto.tracing`.
