[unitaryhack] Deprecate `qml.inv`
*This issue has been tagged for contributions during [unitaryHACK](https://unitaryfund.github.io/unitaryhack/participating-projects.html)*

Currently, PennyLane has two functions for inverting quantum operations:

* [`qml.inv()`](https://github.com/PennyLaneAI/pennylane/blob/4ece39acb42dacafd5b5cc566c4d3f0512dfa6fb/pennylane/utils.py#L236) accepts a list of operations, unqueues them from the tape, inverts them, and re-queues.

* [`qml.adjoint()`](https://github.com/PennyLaneAI/pennylane/blob/master/pennylane/transforms/adjoint.py) transforms a function that queues operations to one that queues the inverse.

While both have very different internal implementations, for end users, they provide pretty much the same functionality; `qml.adjoint()`, however, is more general and `qml.inv()` has been marked for removal.

Further, the term `adjoint` is already in use for the adjoint differentiation method, and could be confusing to have two independent concepts share the same term.

So we can kill two birds with one stone:

- Remove `qml.inv()`
- Rename the `qml.adjoint()` transform to `qml.inv()`.

This has the advantage that existing users code that uses `qml.inv()` should continue to work as is.

### Additional contract requirements

The required change is to deprecate the existing `qml.inv()` utility (`pennylane.utils.inv`) by emitting a `UserWarning` when it is called, while preserving its existing behaviour so that current user code continues to work. The `qml.adjoint()` transform keeps its current name; it is not renamed to `qml.inv()`.
