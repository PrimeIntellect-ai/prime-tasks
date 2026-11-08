Helidon 4.0.9 gets NPE on context aware wrapped async virtual thread use in JaegerDataPropagationProvider.java:41

## Environment Details
* Helidon Version: 4.0.9 SE
* JDK version: Graal 21
* OS: OL 7u5

----------

## Problem Description
Working tests in 4.0.8 are getting NPE in 4.0.9

[ERROR] validate.helidon.tracing.TracerPropagationTest.concurrentVirtualThreadUseCanary  Time elapsed: 0.02 s  <<< ERROR!
java.lang.NullPointerException: Cannot invoke "io.helidon.tracing.providers.opentelemetry.OpenTelemetryDataPropagationProvider$OpenTelemetryContext.tracer()" because "delegate" is null
	at io.helidon.tracing.providers.jaeger@4.0.9/io.helidon.tracing.providers.jaeger.JaegerDataPropagationProvider$JaegerContext.<init>(JaegerDataPropagationProvider.java:41)

(complete stack will be uploaded)

## Steps to reproduce
See uploaded test class that passes in 4.0.8 and fails in 4.0.9

### Additional contract requirements

- Context-wrapped asynchronous work running on virtual threads must retain access to the caller’s tracer and active span, so it can create and activate a child span whose parent is the propagated span.
