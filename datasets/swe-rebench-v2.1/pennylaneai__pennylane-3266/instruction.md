[BUG] Wires are not checked when computing the `expval` of a `Hamiltonian` with `shots=None`
### Expected behavior

The attached code should raise the error:
```
pennylane.wires.WireError: Did not find some of the wires (0, 1) on device with wires (0,).
```

### Actual behavior

It runs and returns an incorrect value.

### Additional information

[HIDDEN]

### Source code

```shell
import pennylane as qml

device = qml.device("default.qubit", wires=1)

H = 1.5 * qml.PauliZ(0) @ qml.PauliZ(1) + 0.3 * qml.PauliX(1)

@qml.qnode(device)
def circuit():
    return qml.expval(H)

print(circuit())
```


### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.27.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/albertmitjans/Developer/pennylane/.venv/lib/python3.9/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Forest, PennyLane-Lightning, PennyLane-qiskit, PennyLane-SF

Platform info:           macOS-13.0-arm64-arm-64bit
Python version:          3.9.13
Numpy version:           1.23.2
Scipy version:           1.9.0
Installed devices:
- default.gaussian (PennyLane-0.27.0.dev0)
- default.mixed (PennyLane-0.27.0.dev0)
- default.qubit (PennyLane-0.27.0.dev0)
- default.qubit.autograd (PennyLane-0.27.0.dev0)
- default.qubit.jax (PennyLane-0.27.0.dev0)
- default.qubit.tf (PennyLane-0.27.0.dev0)
- default.qubit.torch (PennyLane-0.27.0.dev0)
- default.qutrit (PennyLane-0.27.0.dev0)
- null.qubit (PennyLane-0.27.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.26.0)
- qiskit.aer (PennyLane-qiskit-0.24.0)
- qiskit.basicaer (PennyLane-qiskit-0.24.0)
- qiskit.ibmq (PennyLane-qiskit-0.24.0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.24.0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.24.0)
- forest.numpy_wavefunction (PennyLane-Forest-0.24.0)
- forest.qvm (PennyLane-Forest-0.24.0)
- forest.wavefunction (PennyLane-Forest-0.24.0)
- strawberryfields.fock (PennyLane-SF-0.20.1)
- strawberryfields.gaussian (PennyLane-SF-0.20.1)
- strawberryfields.gbs (PennyLane-SF-0.20.1)
- strawberryfields.remote (PennyLane-SF-0.20.1)
- strawberryfields.tf (PennyLane-SF-0.20.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- When computing the expectation value of a Hamiltonian with `shots=None`, raise `pennylane.wires.WireError` if the Hamiltonian uses any wire that is not present on the device.
