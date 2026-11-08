otelgrpc: performance issue about otlpreceiver invoke proto.Size slow path
The opentelemetry collector otlpreceiver consume lots of cpu for proto.Size, marshal to buffer, get buffer size.

related https://github.com/open-telemetry/opentelemetry-collector/issues/6947

[HIDDEN]

### Additional contract requirements

- The gRPC message event recorded on a span must contain the message type (`message.type`) and the message identifier (`message.id`) attributes, and must not contain an uncompressed message size attribute (`message.uncompressed_size`).
- Recording a gRPC message event must not calculate the protobuf size of its payload.
