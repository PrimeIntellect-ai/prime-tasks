[BUG] Incorrect answers from qml.var due to sum hashing
### Expected behavior

Given some circuit like this,

```
dev = qml.device("default.qubit", wires=3)

@qml.qnode(dev)
def circuit_separated():
    qml.RX(np.pi / 3, 0)
    qml.RZ(np.pi / 3, 0)
    return [
        qml.var(qml.Z(0)), qml.var(qml.X(0))
    ]

>>> circuit_separated()
[tensor(0.75, requires_grad=True), tensor(0.4375, requires_grad=True)] # As expected
```

You expect the summed version to be
```
dev = qml.device("default.qubit", wires=3)

@qml.qnode(dev)
def circuit_summed():
    qml.RX(np.pi / 3, 0)
    qml.RZ(np.pi / 3, 0)
    return [
        qml.var(qml.Z(0) + qml.X(0))
    ]

>>> circuit_summed()
[tensor(0.75+0.4375, requires_grad=True)]
```

Furthermore,
When changing the circuit you expect the answer to change

```
dev = qml.device("default.qubit", wires=3)

@qml.qnode(dev)
def circuit_summed():
    qml.RX(np.pi / 3, 0)
    qml.RZ(np.pi / 3, 0)
    return [
        qml.var(qml.Z(0) + qml.X(0) + qml.Z(0) + qml.Z(0) + qml.Z(0)) # in fact you can add as many qml.Z(0) and qml.X(0)'s you want
    ]

>>> circuit_summed()
# should be some new answer
```


### Actual behavior

```
dev = qml.device("default.qubit", wires=3)
@qml.qnode(dev)
def circuit_summed():
    qml.RX(np.pi / 3, 0)
    qml.RZ(np.pi / 3, 0)
    return [
        qml.var(qml.Z(0) + qml.X(0))
    ]

circuit_summed()
>>> [tensor(0.4375, requires_grad=True)] # That's odd
```

If you don't restart kernel:
```
dev = qml.device("default.qubit", wires=3)

@qml.qnode(dev)
def circuit_summed():
    qml.RX(np.pi / 3, 0)
    qml.RZ(np.pi / 3, 0)
    return [
        qml.var(qml.Z(0) + qml.X(0) + qml.Z(0) + qml.Z(0) + qml.Z(0)) # in fact you can add as many qml.Z(0) and qml.X(0)'s you want
    ]

>>> circuit_summed()
[tensor(0.4375, requires_grad=True)] # That's odd, it's still the same answer!
```

If you restart kernel the answer changes:
```
>>> circuit_summed()
[tensor(9.4375, requires_grad=True)] # Not sure if correct though
```


### Additional information

_No response_

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.37.0.dev0
Summary: PennyLane is a cross-platform Python library for quantum computing, quantum machine learning, and quantum chemistry. Train a quantum computer the same way as a neural network.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/austin.huang/pennylane/pennylane-qiskit/venv/lib/python3.11/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, packaging, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: PennyLane_Lightning

Platform info:           macOS-14.5-arm64-arm-64bit
Python version:          3.11.9
Numpy version:           1.26.4
Scipy version:           1.13.1
Installed devices:
- qiskit.aer (PennyLane-qiskit-0.35.0.dev0)
- qiskit.basicaer (PennyLane-qiskit-0.35.0.dev0)
- qiskit.ibmq (PennyLane-qiskit-0.35.0.dev0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.35.0.dev0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.35.0.dev0)
- qiskit.remote (PennyLane-qiskit-0.35.0.dev0)
- default.clifford (PennyLane-0.37.0.dev0)
- default.gaussian (PennyLane-0.37.0.dev0)
- default.mixed (PennyLane-0.37.0.dev0)
- default.qubit (PennyLane-0.37.0.dev0)
- default.qubit.autograd (PennyLane-0.37.0.dev0)
- default.qubit.jax (PennyLane-0.37.0.dev0)
- default.qubit.legacy (PennyLane-0.37.0.dev0)
- default.qubit.tf (PennyLane-0.37.0.dev0)
- default.qubit.torch (PennyLane-0.37.0.dev0)
- default.qutrit (PennyLane-0.37.0.dev0)
- default.qutrit.mixed (PennyLane-0.37.0.dev0)
- default.tensor (PennyLane-0.37.0.dev0)
- null.qubit (PennyLane-0.37.0.dev0)
- lightning.qubit (PennyLane_Lightning-0.36.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

A sum must retain the multiplicity of each identical operand when it is hashed, so sums with different repeat counts are not conflated. A variance measurement of a sum is the variance of the full summed observable, including covariance between terms; it is not generally the sum of the individual variances. For the circuit above, the variance of `Z(0) + X(0)` is `0.4375`, not `0.75 + 0.4375`. For the later circuit containing `Z(0) + X(0) + Z(0) + Z(0) + Z(0)`, the variance is `9.4375`.
