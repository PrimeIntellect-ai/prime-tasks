protocol configuration for grpc is incorrect
### Description

The `otlp.protocol` configuration for exporters currently checks if the protocol matches the string `grpc/protobuf`, it should be checking for `grpc` instead to match the specification https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/exporter.md#configuration-options
