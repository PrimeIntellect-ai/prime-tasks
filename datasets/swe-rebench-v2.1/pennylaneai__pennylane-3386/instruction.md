[BUG] qml.matrix(op) and op.matrix() are different for Barrier and WireCut
### Expected behavior

I expected them both to pass, or both to fail.

### Actual behavior

`qml.matrix(qml.Barrier(0))` passed, `qml.Barrier(0).matrix()` failed. Same for `qml.WireCut`.

### Additional information

Attached source code is for Barrier, but the same thing happens with WireCut.

### Source code

```shell
>>> import pennylane as qml
>>> op = qml.Barrier(0)
>>> qml.matrix(op)
array([[1.]])
>>> op.matrix()
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/matthews/src/github.com/PennyLaneAI/pennylane/pennylane/operation.py", line 1405, in matrix
    canonical_matrix = self.compute_matrix(*self.parameters, **self.hyperparameters)
  File "/Users/matthews/src/github.com/PennyLaneAI/pennylane/pennylane/operation.py", line 446, in compute_matrix
    raise MatrixUndefinedError
pennylane.operation.MatrixUndefinedError
```


### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.27.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/matthews/.pyenv/versions/3.9.13/envs/pennylane/lib/python3.9/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           macOS-12.6.1-arm64-arm-64bit
Python version:          3.9.13
Numpy version:           1.23.2
Scipy version:           1.9.0
Installed devices:
- default.gaussian (PennyLane-0.27.0)
- default.mixed (PennyLane-0.27.0)
- default.qubit (PennyLane-0.27.0)
- default.qubit.autograd (PennyLane-0.27.0)
- default.qubit.jax (PennyLane-0.27.0)
- default.qubit.tf (PennyLane-0.27.0)
- default.qubit.torch (PennyLane-0.27.0)
- default.qutrit (PennyLane-0.27.0)
- null.qubit (PennyLane-0.27.0)
- lightning.qubit (PennyLane-Lightning-0.26.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
