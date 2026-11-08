[BUG] Using qml.apply on measurementProcess separated by commas returns ()
### Expected behavior

I am trying to use qml.apply to write test cases, specifically to parametrize across many different measurementProcesses. Some of these MPs look something like this:

```
dev = qml.device("default.qubit", wires=2, shots=1024)

op = qml.sample(qml.X(0) + qml.Y(0)), qml.sample(qml.X(0))
@qml.qnode(dev)
def circuit():
    qml.RX(np.pi / 3, 0)
    qml.RZ(np.pi / 3, 0)
    return qml.apply(op)

circuit()
```

This circuit should raise an error.

### Actual behavior

It returns `()` without any indication of anything going wrong.

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
