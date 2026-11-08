Batched Span Processor
Add Batched Span Processor that collects all the spans and asynchronously process them.
Allow batch size and batch delay configuration.

### Additional contract requirements

In package `go.opentelemetry.io/sdk/trace`:

- Add a public interface `BatchExporter` with method `ExportSpans(sds []*SpanData)`.
- Add a public type `BatchSpanProcessor`.
- Add a public type `BatchSpanProcessorOption`.
- Add a public function `NewBatchSpanProcessor(exporter BatchExporter, opts ...BatchSpanProcessorOption) (*BatchSpanProcessor, error)` that returns a non-nil error when `exporter` is nil.
- Add a public function `WithScheduleDelayMillis(delay time.Duration) BatchSpanProcessorOption` that sets the interval between successive batch exports.
- Add a public function `WithMaxQueueSize(size int) BatchSpanProcessorOption` that sets the maximum number of spans that can be queued.
- Add a public function `WithMaxExportBatchSize(size int) BatchSpanProcessorOption` that sets the maximum number of spans exported in a single batch.
- Add a public function `WithBlocking() BatchSpanProcessorOption` that makes the processor block when the queue is full instead of dropping spans.

By default, the maximum queue size is 2048 spans, the maximum export batch size is 512 spans, and the scheduled delay is 5000 milliseconds. When the queue overflows, the first enqueued span must remain queued and be the first span exported. With default options, the processor must export 2048 queued spans in at least four batches within 5100 milliseconds.

`UnregisterSpanProcessor` removes the processor from the SDK and calls its `Shutdown` method so that any spans still buffered by a `BatchSpanProcessor` are exported.
