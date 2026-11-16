Change `SpanExporter::export()` result to `Success` or `Failure`
[Export()](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/sdk.md#exportbatch) defines only `Success` and `Failure`. The differentiation between `STATUS_FAILED_NOT_RETRYABLE` and `STATUS_FAILED_RETRYABLE` isn't useful to the caller as "retry logic is the responsibility of the exporter".

### Additional contract requirements

- `OpenTelemetry\SDK\Trace\SpanExporterInterface::export(iterable $spans, ?CancellationInterface $cancellation = null): FutureInterface<bool>` returns a future that resolves to `true` when the export succeeds and `false` for any failure.
- When `OpenTelemetry\SDK\Trace\SpanExporter\LoggerDecorator` receives a failed export result (`false`), it logs the failure.
