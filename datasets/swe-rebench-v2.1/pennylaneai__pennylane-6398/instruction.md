[BUG] `qml.matrix` gives wrong solutions in `default.qutrit` for more than one wire
### Expected behavior

```python

@qml.qnode(qml.device("default.qutrit", wires = 2))
def circuit():

    qml.TShift(wires=0)
    qml.TShift(wires=1)

    qml.adjoint(qml.TShift)(wires=0)
    qml.adjoint(qml.TShift)(wires=1)

    return qml.state()

print(qml.matrix(circuit, wire_order = [0, 1])())

```

This should return the identity

### Actual behavior

```

[[0 0 0 1 0 0]
 [0 1 0 0 0 0]
 [0 0 0 0 0 1]
 [1 0 0 0 0 0]
 [0 0 0 0 1 0]
 [0 0 1 0 0 0]]
```

### Additional information

The code in this other order works:

```python

@qml.qnode(qml.device("default.qutrit", wires = 2))
def circuit():

    qml.TShift(wires=0)
    qml.adjoint(qml.TShift)(wires=0)

    qml.TShift(wires=1)
    qml.adjoint(qml.TShift)(wires=1)

    return qml.state()

print(qml.matrix(circuit, wire_order = [0, 1])())

```


It is possible that prod is not working properly with qutrits.

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.39.0.dev20
Summary: PennyLane is a cross-platform Python library for quantum computing, quantum machine learning, and quantum chemistry. Train a quantum computer the same way as a neural network.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/guillermoalonso/Documents/GitHub/pennylane
Editable project location: /Users/guillermoalonso/Documents/GitHub/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, packaging, pennylane-lightning, requests, rustworkx, scipy, toml, typing_extensions
Required-by: PennyLane-Catalyst, PennyLane_Lightning

Platform info:           macOS-14.6.1-arm64-arm-64bit
Python version:          3.9.6
Numpy version:           1.26.4
Scipy version:           1.12.0
Installed devices:
- default.clifford (PennyLane-0.39.0.dev20)
- default.gaussian (PennyLane-0.39.0.dev20)
- default.mixed (PennyLane-0.39.0.dev20)
- default.qubit (PennyLane-0.39.0.dev20)
- default.qutrit (PennyLane-0.39.0.dev20)
- default.qutrit.mixed (PennyLane-0.39.0.dev20)
- default.tensor (PennyLane-0.39.0.dev20)
- null.qubit (PennyLane-0.39.0.dev20)
- reference.qubit (PennyLane-0.39.0.dev20)
- sparse.qubit (PennyLane-0.39.0.dev20)
- lightning.qubit (PennyLane-Lightning-0.38.0)
- nvidia.custatevec (PennyLane-Catalyst-0.8.1)
- nvidia.cutensornet (PennyLane-Catalyst-0.8.1)
- oqc.cloud (PennyLane-Catalyst-0.8.1)
- softwareq.qpp (PennyLane-Catalyst-0.8.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- The public function `expand_matrix(mat, wires, wire_order=None, sparse_format="csr")` in `pennylane.math` expands a matrix defined on `wires` to the full set of wires given by `wire_order`, permuting the matrix so that it respects that ordering.
- `expand_matrix` must support qudit dimensions greater than 2 (for example qutrits with dimension 3).
- `expand_matrix` must accept both dense arrays and SciPy sparse matrices, returning a result in the matching format, and must preserve any batch dimensions.
