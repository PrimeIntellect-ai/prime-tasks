autoexport: Add support for Prometheus
* Support `OTLP_METRICS_EXPORTER=prometheus`
* Serve a Prometheus metric endpoint based on the values of `OTEL_EXPORTER_PROMETHEUS_HOST` and `OTEL_EXPORTER_PROMETHEUS_PORT` [[spec](https://github.com/open-telemetry/opentelemetry-specification/blob/563958cb2bd8529990f19fdce7a5f3643bf63091/specification/configuration/sdk-environment-variables.md?plain=1#L201)]

This was partially implemented in https://github.com/open-telemetry/opentelemetry-go-contrib/pull/4229 but then removed in favor of a full implementation in a separate PR.

Previous [discussion](https://github.com/open-telemetry/opentelemetry-go-contrib/pull/4229#discussion_r1364353029) [discussion](https://github.com/open-telemetry/opentelemetry-go-contrib/pull/4229#discussion_r1367350098)

### Additional contract requirements

- Select Prometheus through autoexport by setting `OTEL_METRICS_EXPORTER=prometheus`; the selector is `OTEL_METRICS_EXPORTER`, not `OTLP_METRICS_EXPORTER`.
- `NewMetricReader(ctx context.Context) (metric.Reader, error)` in `exporters/autoexport` returns a non-nil error when the Prometheus HTTP server cannot bind to the configured address, and that error message contains `binding`.
- A successful HTTP GET request to the Prometheus `/metrics` endpoint returns a response body containing `# HELP`.
