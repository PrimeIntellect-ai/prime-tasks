`ResourceInfo` needs a dedicated factory
I believe `ResoerceInfo` needs a dedicated factory. It's overloaded with factory methods, while creating objects is not its main responsibility. However this could be changed in a later PR.

_Originally posted by @tidal in https://github.com/open-telemetry/opentelemetry-php/pull/469#r748851138_

### Additional contract requirements

Default-resource detection and assembly are the responsibility of a dedicated resource factory, separate from the resource value object. `ResourceInfo::create()` represents only the attributes explicitly supplied to it; it does not add SDK defaults. `ResourceInfo::defaultResource()` remains the public entry point for obtaining the SDK-provided default resource. The factory boundary is defined by this separation of observable behavior, not by requiring a separately named public factory class.

`ResourceInfo::defaultResource()` must return a resource whose attributes include, with non-null values, the following semantic-convention keys: `host.name`, `host.arch`, `os.type`, `os.description`, `os.name`, `os.version`, `process.pid`, `process.executable.path`, `process.command`, `process.command_args`, `process.runtime.name`, `process.runtime.version`, `telemetry.sdk.name`, `telemetry.sdk.language`, `telemetry.sdk.version`, and `service.name`. The `telemetry.sdk.name` value must be `opentelemetry`, the `telemetry.sdk.language` value must be `php`, and the `service.name` value must be `unknown_service`.

When resolving `service.name`, `ResourceInfo::defaultResource()` applies the following precedence (highest first): the `OTEL_SERVICE_NAME` environment variable, a `service.name` entry in `OTEL_RESOURCE_ATTRIBUTES`, and finally the SDK default `unknown_service`.
