autoexport: Change WithFallback options signatures
### Problem Statement

The current definition of fallback options is as following:

```go
func WithFallbackMetricReader(exporter metric.Reader) MetricOption
```

The problem is that we need to create an instance of a metric reader or span exporter and it may not even be needed/used (it may even leak resources).

### Proposed Solution

Change the signature to accept a factory function e.g.

```go
func WithFallbackMetricReader(factory func(context.Context) (metric.Reader, error)) MetricOption
```

### Additional contract requirements

- `WithFallbackSpanExporter` in package `go.opentelemetry.io/contrib/exporters/autoexport` accepts a factory `func(ctx context.Context) (trace.SpanExporter, error)` and returns a `SpanOption`.
- `WithFallbackMetricReader` in package `go.opentelemetry.io/contrib/exporters/autoexport` accepts a factory `func(ctx context.Context) (metric.Reader, error)` and returns a `MetricOption`.
- The fallback factory is invoked only when the corresponding exporter environment variable (`OTEL_TRACES_EXPORTER` for span exporters, `OTEL_METRICS_EXPORTER` for metric readers) is unset or empty.
- An error returned by the fallback factory is returned to the caller of `NewSpanExporter` / `NewMetricReader`.
