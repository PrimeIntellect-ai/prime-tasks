[BUG] Incorrect control values in `ControlledQubitUnitary.pow()`
### Expected behavior

For some integer `x` and 2x2 unitary matrix `mat`, using `ControlledQubitUnitary.pow()` has the following expected behaviour:
```pycon
>>> op = qml.ControlledQubitUnitary(mat, control_wires=[0, 1], wires=2, control_values="00")
>>> pow_ops = op.pow(x)
>>> np.allclose(np.linalg.matrix_power(mat, x), pow_ops[0].data[0])
True
>>> pow_ops[0].hyperparameters["control_values"]
00
```

### Actual behavior

For some integer `x` and 2x2 unitary matrix `mat`, using `ControlledQubitUnitary.pow()` has the following **actual** behaviour:
```pycon
>>> op = qml.ControlledQubitUnitary(mat, control_wires=[0, 1], wires=2, control_values="00")
>>> pow_ops = op.pow(x)
>>> np.allclose(np.linalg.matrix_power(mat, x), pow_ops[0].data[0])
True
>>> pow_ops[0].hyperparameters["control_values"]
None
```


### Additional information

This is because the `pow` method doesn't update the `control_values` hyperparameter for the returned `ControlledQubitUnitary` list.

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
This isn't included because the issue is related to an incorrect implementation of ControlledQubitUnitary.pow()
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
