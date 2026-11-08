QNodes with `default.qubit` and `default.qubit.legacy` give different results
### Expected behavior

They should give the same results.

### Actual behavior

They give different results.

### Additional information

Seems to be that BasisState followed by some (? — RandomLayers and some instances of QubitUnitary ) operation give different results.

### Source code

```shell
import pennylane as qml
import pennylane.numpy as np

new_device = qml.device("default.qubit", wires=2)
legacy_device = qml.device("default.qubit.legacy", wires=2)

def random_unitary():
    weights = np.array([[0.1, -2.1, 1.4]])
    qml.RandomLayers(weights=weights, wires=0)

def circuit(state):
    qml.BasisState(state, wires=1)
    random_unitary()
    # getting rid of BasisState and/or random_unitary produces no discrepancy

@qml.qnode(new_device)
def circuit_new_device(state):
    circuit(state)
    return qml.state()

@qml.qnode(legacy_device)
def circuit_legacy_device(state):
    circuit(state)
    return qml.state()

res_new_device = circuit_new_device(np.array([1]))
res_legacy_device = circuit_legacy_device(np.array([1]))

print(res_new_device == res_legacy_device) # [False False False False]
```


### Tracebacks

```shell
N/A
```


### System information

```shell
Name: PennyLane
Version: 0.33.0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/isaac/.virtualenvs/pennylane-stable/lib/python3.9/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: PennyLane-Lightning

Platform info:           macOS-14.1-x86_64-i386-64bit
Python version:          3.9.14
Numpy version:           1.23.5
Scipy version:           1.10.0
Installed devices:
- default.gaussian (PennyLane-0.34.0.dev0)
- default.mixed (PennyLane-0.34.0.dev0)
- default.qubit (PennyLane-0.34.0.dev0)
- default.qubit.autograd (PennyLane-0.34.0.dev0)
- default.qubit.jax (PennyLane-0.34.0.dev0)
- default.qubit.legacy (PennyLane-0.34.0.dev0)
- default.qubit.tf (PennyLane-0.34.0.dev0)
- default.qubit.torch (PennyLane-0.34.0.dev0)
- default.qutrit (PennyLane-0.34.0.dev0)
- null.qubit (PennyLane-0.34.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.33.1)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- `DefaultQubit` is importable from `pennylane.devices` and provides a method `execute(self, tape)` that accepts a `qml.tape.QuantumScript` and returns the full state vector as a complex-valued array.
- `qml.tape.QuantumScript(ops, measurements)` constructs a quantum program from a list of operations and a list of measurements.
- The state vector returned by `DefaultQubit.execute` is ordered according to the device's wire ordering (the device's wires in increasing order), independent of the order in which wires appear in the tape's operations.
