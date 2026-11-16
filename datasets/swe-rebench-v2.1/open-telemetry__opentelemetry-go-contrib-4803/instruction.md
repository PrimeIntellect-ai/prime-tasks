Upgrade all resource detectors to use go.opentelemetry.io/otel/semconv/v1.24.0
Related issue: https://github.com/open-telemetry/opentelemetry-go/issues/4753

### Additional contract requirements

- Every resource produced by the upgraded detectors must carry the schema URL
  `https://opentelemetry.io/schemas/1.24.0` (the `SchemaURL` value of
  `go.opentelemetry.io/otel/semconv/v1.24.0`).
