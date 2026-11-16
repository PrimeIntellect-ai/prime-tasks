[BUG] `qml.center` does not work for all linear combinations of Paulis
### Expected behavior

`qml.center` always computes the center of an algebra.

### Actual behavior

If the algebra basis is such that the center elements are linear combinations of them, `qml.center` does not find them.

### Additional information

[HIDDEN]

### Source code

```shell
>>> dla = qml.lie_closure([qml.X(0), qml.X(1), (qml.X(0)@qml.X(1) + qml.Y(0) @ qml.Y(1) + qml.Z(0)@ qml.Z(1))])
>>> print(dla)
[X(0),
 X(1),
 X(0) @ X(1) + Y(0) @ Y(1) + Z(0) @ Z(1),
 Z(0) @ Y(1) + -1.0 * (Y(0) @ Z(1)),
 -1.0 * (Y(0) @ Y(1)) + -1.0 * (Z(0) @ Z(1))]
>>> qml.center(dla)
[] # Should contain X(0) + X(1)
```


### Tracebacks

_No response_

### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- The center is returned as a list of operators whose linear span is the center of the algebra. For the motivating example above, `X(0) + X(1)` lies in the span of the returned list.
- For `c = 1 / sqrt(2)`, the center returned for `qml.lie_closure([qml.X(0), qml.X(1), qml.Y(0) @ qml.Y(1) + qml.Z(0) @ qml.Z(1)])` must span `c * qml.X(0) + c * qml.X(1)`.
- When the input is a list of `PauliSentence` instances that span an algebra whose center is one-dimensional and spanned by `X(0)`, `qml.center(..., pauli=False)` must return a one-element list whose element is an `qml.ops.op_math.SProd` with base `qml.X(0)`; with `pauli=True`, it must return a one-element list whose element is a `PauliSentence` containing `PauliWord({0: "X"})`.
