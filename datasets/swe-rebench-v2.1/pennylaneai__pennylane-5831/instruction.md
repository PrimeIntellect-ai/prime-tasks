[BUG] `qml.simplify` removes information regarding `num_steps` from `Exp`
### Expected behavior

``` py
>>> op1 = qml.exp(qml.Z(0) + 1.2*qml.Z(1), -1.2j, num_steps=2)
>>> qml.simplify(op1).num_steps
2
```

### Actual behavior

``` py
>>> op1 = qml.exp(qml.Z(0) + 1.2*qml.Z(1), -1.2j, num_steps=2)
>>> qml.simplify(op1).num_steps
None
```

### Additional information

![image](https://github.com/PennyLaneAI/pennylane/assets/23234279/fb98b52f-f33a-4210-b8dc-37c23aa1dd5c)


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
Location: /Library/Frameworks/Python.framework/Versions/3.10/lib/python3.10/site-packages
Editable project location: /Users/utkarsh/Xanadu/Codes/SourceCodes/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing-extensions
Required-by: amazon-braket-pennylane-plugin, PennyLane-Catalyst, PennyLane-Cirq, PennyLane-qiskit, PennyLane_Lightning, PennyLane_Lightning_Kokkos, quantum-datasets

Platform info:           macOS-13.6.7-arm64-arm-64bit
Python version:          3.10.4
Numpy version:           1.22.4
Scipy version:           1.12.0
Installed devices:
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
- lightning.kokkos (PennyLane_Lightning_Kokkos-0.36.0)
- lightning.qubit (PennyLane_Lightning-0.36.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
