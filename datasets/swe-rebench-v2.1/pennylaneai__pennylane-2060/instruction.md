Raise exception or warning when `qml.adjoint` is used on operation list instead of function.
The newer `qml.adjoint` function does not have any effect when acting on operation lists like in the following example:
```python
params = list(range(4))
qml.adjoint(qml.templates.AngleEmbedding(params))
```
Users might try this, because it worked like this with `qml.inv` which `qml.adjoint` is replacing. Therefore, we should raise
an exception whenever this is attempted [HIDDEN]. Alternatively, a warning could be raised, but
the behaviour differs fundamentally from the expected, an exception seems more appropriate.

### Additional contract requirements

- `qml.adjoint` must signal when given any non-callable input rather than silently accepting it; it may raise an exception or issue a warning.
