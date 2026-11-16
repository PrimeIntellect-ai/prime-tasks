`TracerProviderHelper#currentSpan()` throws NPE in some situations
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
In some limited cases, the `TracerProviderHelper#currentSpan` method throws a NPE because `TRACER_PROVIDER` is null when `currentSpan` is invoked.

In at least two situations, customer code uses a custom `TracerProvider`. The static initializer in Helidon's `TracerProviderHelper` class uses service loading to locate and load such implementations, select one, and store a reference to it in the `TRACER_PROVIDER` static field.

During its own initialization, that custom `TracerProvider` uses logging, and there is a custom logger in place which attempts to get the current span (if any) to add to log messages. And the attempt to get the current span ultimately invokes `TracerProviderHelper.currentSpan()` which depends on `TRACER_PROVIDER` being non-null.

In this scenario, though, `TRACER_PROVIDER` is still null because the static initializer has not yet finished. That triggers the NPE.

Although one could argue that the custom `TracerProvider` should not, even indirectly, invoke code that relies on `TRACER_PROVIDER` being non-null, this use case (and ones like it) would be difficult to untangle. Helidon could be of help to users in these situations by anticipating and dealing with this edge case.
