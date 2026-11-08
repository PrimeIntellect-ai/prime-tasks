add support for multiple log record processors
The logging spec indicates that a logger provider can be configured with multiple `LogRecordProcessor`s:
https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/logs/sdk.md#logrecordprocessor

### Additional contract requirements

- `OpenTelemetry\SDK\Logs\LoggerProviderBuilder::addLogRecordProcessor(LogRecordProcessorInterface $processor): LoggerProviderBuilder` registers an additional log record processor and returns the same builder instance, so that multiple processors can be added before the provider is built.
- `OpenTelemetry\SDK\Logs\LoggerSharedState::forceFlush(?CancellationInterface $cancellation = null): bool` forces buffered log records to be exported immediately and returns whether the underlying processor flushed successfully.
- `OpenTelemetry\SDK\Logs\Processor\MultiLogsProcessor` is a log record processor that combines an array of `LogRecordProcessorInterface` instances, constructed as `new MultiLogsProcessor(array $processors)`:
  - `onEmit(ReadWriteLogRecord $record, ?ContextInterface $context = null): void` forwards the record and context to every contained processor.
  - `shutdown(?CancellationInterface $cancellation = null): bool` shuts down every contained processor and returns `true` only if all of them shut down successfully.
  - `forceFlush(?CancellationInterface $cancellation = null): bool` flushes every contained processor and returns `true` only if all of them flush successfully.
