[BUG] `qml.Adjoint` and `qml.Pow` do not commute when exponent is fractional
### Expected behavior

Taking the `qml.adjoint()` of a powered-operator, i.e. an operator resulting from `qml.pow`, returns the same result whether we use `lazy=True` or `lazy=False` in `qml.adjoint()`.

### Actual behavior

Setting the flag `lazy=False` when using a fractional power (`z`) in `qml.pow` produces a matrix with the imaginary component having the opposite sign as with `lazy=True`. The correct matrix is the one with `lazy=True`

### Additional information

_No response_

### Source code

```shell
import pennylane as qml

power = 0.5
op = qml.Hadamard(0)
powered_op = qml.pow(op, power, lazy=True)

powered_op_adj_true = qml.adjoint(powered_op, lazy=True)
matrix_true = qml.matrix(powered_op_adj_true)

powered_op_adj_false = qml.adjoint(powered_op, lazy=False)
matrix_false = qml.matrix(powered_op_adj_false)

np.allclose(matrix_true, matrix_false)
>> False
```


### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.36.0
Summary: PennyLane is a cross-platform Python library for quantum computing, quantum machine learning, and quantum chemistry. Train a quantum computer the same way as a neural network.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/emiliano.godinez/Documents/software_development/pennylane-iqm/venv/lib/python3.9/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: pennylane_iqm, PennyLane_Lightning

Platform info:           macOS-14.5-arm64-arm-64bit
Python version:          3.9.19
Numpy version:           1.26.4
Scipy version:           1.13.1
Installed devices:
- iqm.remote (pennylane-iqm-0.0.1)
- default.clifford (PennyLane-0.36.0)
- default.gaussian (PennyLane-0.36.0)
- default.mixed (PennyLane-0.36.0)
- default.qubit (PennyLane-0.36.0)
- default.qubit.autograd (PennyLane-0.36.0)
- default.qubit.jax (PennyLane-0.36.0)
- default.qubit.legacy (PennyLane-0.36.0)
- default.qubit.tf (PennyLane-0.36.0)
- default.qubit.torch (PennyLane-0.36.0)
- default.qutrit (PennyLane-0.36.0)
- default.qutrit.mixed (PennyLane-0.36.0)
- null.qubit (PennyLane-0.36.0)
- lightning.qubit (PennyLane-Lightning-0.36.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- `Pow.has_adjoint` is `True` when the stored exponent `z` is an instance of `int`, and `False` otherwise.
- `Pow.adjoint()` returns a new `Pow` whose base is the adjoint of the original base when `z` is an integer, and raises `pennylane.operation.AdjointUndefinedError` when `z` is not an integer.
- When `z` is not an integer, the raised `AdjointUndefinedError` message contains `The adjoint of Pow operators`.
