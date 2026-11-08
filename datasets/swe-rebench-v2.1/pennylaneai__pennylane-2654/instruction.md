Remove `qml.utils.expand`
### Feature details

It seems that the utility function `qml.utils.expand` is no longer used anywhere as of #2609.
It therefore could be removed. A differentiable, more up-to-date version is available in `qml.operation.expand_matrix`.

### Implementation

_No response_

### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

_No response_

### Additional contract requirements

- `qml.operation.expand_matrix(base_matrix, wires, wire_order)` is the public replacement for the removed utility. Given a square operator matrix acting on the subspace given by `wires`, it returns a square matrix of size `2**len(wire_order)` that represents the same operator expressed on the full `wire_order`.
- The old `qml.utils.expand` entry point remains accessible for backward compatibility. Accessing `qml.utils.expand` emits a `UserWarning` whose message is exactly `qml.utils.expand is deprecated; using qml.operation.expand_matrix instead.` and yields the same expansion behaviour as `qml.operation.expand_matrix`.
