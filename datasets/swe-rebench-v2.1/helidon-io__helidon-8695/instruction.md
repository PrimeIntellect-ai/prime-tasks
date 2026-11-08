`JaegerTracerBuilder` `propagatorFormats` property retains initial default value even when explicitly set
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
The `propagatorFormats` property of `JaegerTracerBuilder` is a `List` property with a default value which incorrectly remains even when `addPropagatorFormat` explicitly adds a value to the property.

This is not an issue in 3.x because in 3.x there is no assigned default value for `propagatorFormats`.

## Steps to reproduce
1. Use `helidon init` to create a custom SE app with Jaeger tracing.
2. Customize the generated `TracedResource` class inner record `TracedHandler#handle` method, adding these lines after the `Span` is instantiated:

   ```java
   SpanContext spanContext = span.context();
   HeaderConsumer headerConsumer = HeaderConsumer.create(new HashMap<>());
   tracer.inject(spanContext, null, headerConsumer);
   ```
3. Customize the `application.yaml` file:
   ```yaml
      tracing:
        service: helidon-tracing-service
        propagation: "b3"
   ```
4. Build the project and run it with the debugger.
5. Set a breakpoint just after the `tracer.inject` line.
6. Submit `curl http://localhost:8080/traced`.
7. At the breakpoint examine the headers in the `HeaderConsumer`. You will find the unexpected header `uber-trace-id` which comes from the Jaeger propagator. You also find the expected `b3` headers from the explicitly-selected `B3` propagator.

   If you open the variable `tracer -> propagator -> textMapPropagators` you see the `JaegerPropagator` unexpectedly included which explains the unexpected `uber` header.
