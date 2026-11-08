NPE in io.opentelemetry.api.baggage.BaggageEntry.getValue() using alternatives to deprecated Span baggage calls
## Environment Details
* Helidon Version: 4.0.10 SE
* JDK version: 21
* OS: OL7
----------

## Problem Description
Changes in Helidon SE 4.0.5 io.helidon.tracing.Span deprecated longstanding baggage calls.
Specifically `String baggage(String key)`
But trying to use the alternatives in some cases cause NPE when baggage is untouched in the span.

## Steps to reproduce
See uploaded standalone test cases
[BaggageOptionalTest.java.txt](https://github.com/user-attachments/files/15820473/BaggageOptionalTest.java.txt)
