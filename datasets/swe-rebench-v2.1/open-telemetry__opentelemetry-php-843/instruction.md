SDK should drop `enduser.*` attributes by default
[General identity attributes](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/span-general.md#general-identity-attributes):
> Given the sensitive nature of this information, SDKs and exporters SHOULD drop these attributes by default and then provide a configuration parameter to turn on retention for use cases where the information is required and would not violate any policies or regulations.

### Additional contract requirements

- `OpenTelemetry\SDK\Trace\SpanLimitsBuilder` exposes a public method `retainGeneralIdentityAttributes(bool $retain = true): SpanLimitsBuilder`. Calling it with `true` retains the general-identity attributes `enduser.id`, `enduser.role` and `enduser.scope` in the built span limits; calling it with `false`, or not calling it at all, drops those attributes. The method returns the builder so calls can be chained, and the most recent call determines the resulting behaviour.
