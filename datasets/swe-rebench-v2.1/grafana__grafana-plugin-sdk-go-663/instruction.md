Tracing: Support multiple OTEL propagators
<!-- Please only use this template for submitting enhancement requests -->

**What would you like to be added**:

Corresponding work for https://github.com/grafana/grafana/pull/61199 in the plugins sdk

**Why is this needed**:

Match behaviour of core grafana

### Additional contract requirements

Add a public function `InitializeForTestsWithPropagatorFormat(propagatorFormat string) (trace.Tracer, error)` in package `internal/tracerprovider`.

- `propagatorFormat` names one or a comma-separated list of OpenTelemetry propagator formats. The supported formats are `"jaeger"` and `"w3c"`.
- The function returns a tracer that records spans, and it configures the global OpenTelemetry tracer provider so that the global provider also records spans.
- The function installs a text-map propagator for the requested format(s): a `"w3c"` request propagates the W3C `traceparent` header, a `"jaeger"` request propagates the Jaeger `uber-trace-id` header, and a comma-separated list propagates all requested formats.
- If the format is unsupported, the function returns a non-nil error.

Add a public function `InitializeForTests() (trace.Tracer, error)` in package `internal/tracerprovider` that returns a tracer configured with the default propagator set `"jaeger,w3c"` (both Jaeger and W3C propagation active).

Normal SDK tracing configuration must also support configuring multiple propagator formats together; when multiple supported formats are configured, propagation uses each of them.
