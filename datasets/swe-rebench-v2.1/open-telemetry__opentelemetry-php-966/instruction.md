Do not include dropped attribute/links/event counts if there are none
We're including these properties all the time, but the spec says they shouldn't be set if they're `0`.

> This key-value pair should only be recorded when it contains a non-zero value.

Ref: https://github.com/open-telemetry/opentelemetry-specification/blob/v1.6.1/specification/trace/sdk_exporters/non-otlp.md#dropped-attributes-count

_Originally posted by @Blacksmoke16 in https://github.com/open-telemetry/opentelemetry-php/pull/422#discussion_r718126627_

### Additional contract requirements

- Converted spans must omit dropped-attribute, dropped-link, and dropped-event counts when their corresponding count is zero. Converted event annotations must likewise omit the dropped-attribute count when the event has dropped no attributes.
- When present, the span fields are named `otel.dropped_attributes_count`, `otel.dropped_links_count`, and `otel.dropped_events_count`, respectively. The dropped-attribute count on event annotations is named `otel.dropped_attributes_count`.
