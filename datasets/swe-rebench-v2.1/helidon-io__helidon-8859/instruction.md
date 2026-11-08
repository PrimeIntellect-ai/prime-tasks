[HIDDEN]
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
In a recent PR, the OTel implementation of the Helidon neutral `Tracer` interface implementation of the `unwrap` method added checking of the Helidon wrapper object as well as the delegate.

But that change [HIDDEN], which changes some behavior (such as unwrapping as `Object` and printing the unwrapped object's `toString()` value). This is also the opposite order that the pre-existing OpenTracing `Tracer` `unwrap` method checks the two objects.

## Steps to reproduce
With the OTel tracing provider in use, invoke `helidonTracer.unwrap(Object.class).toString()` and you see the Helidon wrapper's value, not the delegate's value as before.

### Additional contract requirements

- With the OTel tracing provider in use, `helidonTracer.unwrap(Object.class)` must return the delegate, not the Helidon wrapper.
- When the requested type matches both the OTel delegate and the Helidon wrapper, `unwrap` must prefer and return the delegate.
