Decode values from `OTEL_RESOURCE_ATTRIBUTES`
While using the Go SDK I noticed an inconsistency in how `OTEL_RESOURCE_ATTRIBUTES` baggage values are encoded and decoded. This was due to a difference in the version of the W3C Baggage spec used for [baggage propagation](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/baggage/api.md#propagation) and the [`OTEL_RESOURCE_ATTRIBUTES` decoding](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/sdk.md#specifying-resource-information-via-an-environment-variable).

https://github.com/open-telemetry/opentelemetry-specification/pull/2670 updates the W3C Baggage spec version used by the Resource spec to require percent-decoding values from  `OTEL_RESOURCE_ATTRIBUTES`.
