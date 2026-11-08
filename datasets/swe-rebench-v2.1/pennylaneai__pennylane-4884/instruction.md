[BUG] `qml.map_wires` does not work correctly with `qml.cond`
### Expected behavior

The mid-circuit measurements that a `qml.cond` depends on are mapped to the new wires correctly.

### Actual behavior

The wires of the measurements used to control the `qml.cond` are not mapped.

### Additional information

_No response_

### Source code

```shell
with qml.queuing.AnnotatedQueue() as q:
    m = qml.measure("a")
    qml.cond(m, qml.PauliZ)("b")

qs = qml.tape.QuantumScript.from_queue(q)
[tape], _ = qml.map_wires(qs, {"a": 0, "b": 1})
tape.operations[1].meas_val.measurements
```


### Tracebacks

```shell
[measure(wires=['a'])]
```


### System information

```shell
Name: PennyLane
Version: 0.34.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/PennyLaneAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/mudit.pandey/repos/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, rustworkx, scipy, semantic-version, toml, typing_extensions
Required-by: PennyLane-Lightning

Platform info:           macOS-13.6.1-arm64-arm-64bit
Python version:          3.10.12
Numpy version:           1.26.1
Scipy version:           1.11.1
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
