[BUG] `qml.is_commuting` breaks with `Tensor` operators.
If we try to check commutation of `Tensor` objects with `qml.is_commuting`, we get:

```
>>> qml.is_commuting(qml.PauliX(0) @ qml.PauliX(1), qml.PauliX(0) @ qml.PauliY(2))
----> 1 qml.is_commuting(qml.PauliX(0) @ qml.PauliX(1), qml.PauliX(0) @ qml.PauliY(2))

File pennylane/pennylane/ops/functions/is_commuting.py:356, in is_commuting(operation1, operation2)
    354 # Check if operations are non simplified rotations and return commutation if it is the case.
    355 op_set = {"U2", "U3", "Rot", "CRot"}
--> 356 if operation1.name in op_set and operation2.name in op_set:
    357     return check_commutation_two_non_simplified_rotations(operation1, operation2)
    359 ctrl_base_1 = _get_target_name(operation1)

TypeError: unhashable type: 'list'
```

We should either:
1) Explicitly not support Tensor operations
2) Include the logic from `qml.grouping.is_commuting` and actually determine whether or not the objects commute.


The first would only be an option for the short term if we don't want to spend the time improving `qml.is_commuting` right now.

### Additional contract requirements

- `qml.is_commuting` is a public function with the signature `is_commuting(operation1, operation2, wire_map=None)`.
- For two Pauli-word inputs, including Pauli-word tensors, `qml.is_commuting` returns whether the two operations commute. The optional `wire_map` argument maps the wire labels used in the Pauli words to integer indices; when it is not supplied, the wire map is inferred from the two operations.
- When either input is a `Tensor` that is not a Pauli word, `qml.is_commuting` raises `qml.QuantumFunctionError` with the message `Tensor operations are not supported.`
- For non-Tensor operations the existing commutation behaviour is preserved: operations acting on disjoint wires commute, and supported non-Pauli operations are handled as before.
