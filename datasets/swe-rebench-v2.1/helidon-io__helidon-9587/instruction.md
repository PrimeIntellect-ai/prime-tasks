4.x Assigning `Tracer.global(tracer)` with the OpenTelemetry provider throws a spurious exception
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP SE
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
The Helidon tracing API allows developer code to set the global tracer by invoking `Tracer.global(tracer)`.

Doing so when using the OpenTelemetry tracing provider causes an incorrect exception to be thrown:

```list
Exception in thread "main" java.lang.IllegalArgumentException: Tracer must be an instance of Helidon OpenTelemetry tracer. Please use HelidonOpenTelemetry to create such instance
        at io.helidon.tracing.providers.opentelemetry.OpenTelemetryTracerProvider.global(OpenTelemetryTracerProvider.java:133)
        at io.helidon.tracing.TracerProviderHelper.global(TracerProviderHelper.java:80)
        at io.helidon.tracing.Tracer.global(Tracer.java:50)
```
This happens even if the provided `tracer` is indeed a `HelidonOpenTelemetry` object.

## Steps to reproduce
With a dependency on `helidon-tracing-providers-opentelemetry` and `helidon-tracing-api` add code something like this:
```java
        io.opentelemetry.api.trace.Tracer otelTracer = openTelemetry.getTracer(serviceName);
        Tracer helidonTracer = HelidonOpenTelemetry.create(openTelemetry, otelTracer, Map.of());
        Tracer.global(helidonTracer);
```
The last line triggers the exception even though the provided tracer is of the correct type.

### Additional contract requirements

- Calling `Tracer.global(tracer)` with a tracer created by `HelidonOpenTelemetry.create(...)` must complete without throwing an exception.
- After that call, the supplied tracer must be installed as the global tracer for the application, so that the OpenTelemetry tracing provider reports that a global tracer is available.
