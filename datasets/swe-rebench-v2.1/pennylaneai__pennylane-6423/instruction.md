[BUG] Differentiating `PrepSelPrep` using parameter-shift returns 0s
### Expected behavior

`PrepSelPrep` can be differentiated properly

### Actual behavior

```python
import pennylane as qml

@qml.qnode(qml.device("default.qubit"), diff-method="parameter-shift")
def circuit(params):
    H = qml.Hamiltonian(params, [qml.Z(2), qml.X(1) @ qml.X(2)])
    qml.PrepSelPrep(H, control=[0])
    return qml.expval(qml.PauliZ(0))

>>> x = qml.numpy.array([0.25, 0.75])
>>> qml.jacobian(circuit)(x)
array([0.,  0.])
```

### Additional information

The issue was discovered as part of https://github.com/PennyLaneAI/pennylane/pull/6282, and the relevant tests in `test_prepselprep.py` and `test_quibitization.py` are xfailed, when fixed, remove the xfail from the relevant tests.

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.39.0.dev10
Summary: PennyLane is a cross-platform Python library for quantum computing, quantum machine learning, and quantum chemistry. Train a quantum computer the same way as a neural network.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/astral.cai/Workspace/pennylane/venv/lib/python3.10/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, packaging, pennylane-lightning, requests, rustworkx, scipy, toml, typing-extensions
Required-by: PennyLane-Catalyst, PennyLane_Lightning, PennyLane_Lightning_Kokkos

Platform info:           macOS-15.0-arm64-arm-64bit
Python version:          3.10.14
Numpy version:           1.26.4
Scipy version:           1.12.0
Installed devices:
- default.clifford (PennyLane-0.39.0.dev19)
- default.gaussian (PennyLane-0.39.0.dev19)
- default.mixed (PennyLane-0.39.0.dev19)
- default.qubit (PennyLane-0.39.0.dev19)
- default.qutrit (PennyLane-0.39.0.dev19)
- default.qutrit.mixed (PennyLane-0.39.0.dev19)
- default.tensor (PennyLane-0.39.0.dev19)
- null.qubit (PennyLane-0.39.0.dev19)
- reference.qubit (PennyLane-0.39.0.dev19)
- lightning.qubit (PennyLane_Lightning-0.39.0.dev27)
- lightning.kokkos (PennyLane_Lightning_Kokkos-0.38.0)
- nvidia.custatevec (PennyLane-Catalyst-0.9.0.dev15)
- nvidia.cutensornet (PennyLane-Catalyst-0.9.0.dev15)
- oqc.cloud (PennyLane-Catalyst-0.9.0.dev15)
- softwareq.qpp (PennyLane-Catalyst-0.9.0.dev15)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
