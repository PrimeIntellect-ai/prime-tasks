Implement factory for ResourceInfo
At the moment most of the methods in [ResourceInfo](https://github.com/open-telemetry/opentelemetry-php/blob/main/src/SDK/Resource/ResourceInfo.php) are factory methods. To better comply with [SRP](https://en.wikipedia.org/wiki/Single-responsibility_principle) those methods should be extracted into a factory class.

### Additional contract requirements

- Provide a public class `OpenTelemetry\SDK\Resource\ResourceInfoFactory`.
- `ResourceInfoFactory::emptyResource(): ResourceInfo` returns a resource that has no attributes.
- `ResourceInfoFactory::defaultResource(): ResourceInfo` builds a resource from the detectors selected by the `OTEL_PHP_DETECTORS` environment variable, and returns an empty resource when no detectors are enabled.
- `ResourceInfoFactory::merge(ResourceInfo ...$resources): ResourceInfo` returns a new resource whose attributes are the union of the attributes of the inputs; when the same attribute key occurs in more than one input, the value from the earliest input is kept.
- The factory methods `merge`, `defaultResource` and `emptyResource` are no longer available on `ResourceInfo`.
