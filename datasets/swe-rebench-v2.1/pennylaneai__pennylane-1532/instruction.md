[BUG] Error when applying `qml.adjoint` outside a tape context
* *Expected behavior:* (What you expect to happen)
The documentation for `qml.adjoint` includes the example
```python
qml.adjoint(qml.RX)(0.123, wires=0)
```
  I expect this to produce the gate that is the adjoint.

* *Actual behavior:* (What actually happens)
The following error is thrown, related to there not being an active tape context:
```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
/tmp/ipykernel_480218/666980449.py in <module>
----> 1 qml.adjoint(qml.RX)(0.123, wires=0)

~/Code/PennyLane/pennylane/transforms/adjoint.py in wrapper(*args, **kwargs)
    114     @wraps(fn)
    115     def wrapper(*args, **kwargs):
--> 116         with get_active_tape().stop_recording(), QuantumTape() as tape:
    117             fn(*args, **kwargs)
    118

AttributeError: 'NoneType' object has no attribute 'stop_recording'
```
* *Reproduces how often:* (What percentage of the time does it reproduce?)

Always, and for any choice of gate.

* *System information:* (post the output of `import pennylane as qml; qml.about()`)

Running on the dev branch of #1455 .

```
Name: PennyLane
Version: 0.17.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author: None
Author-email: None
License: Apache License 2.0
Location: /home/olivia/Code/PennyLane
Requires: numpy, scipy, networkx, autograd, toml, appdirs, semantic-version, autoray
Required-by:
Platform info:           Linux-5.8.0-59-generic-x86_64-with-glibc2.31
Python version:          3.9.5
Numpy version:           1.21.0
Scipy version:           1.7.0
Installed devices:
- default.gaussian (PennyLane-0.17.0.dev0)
- default.mixed (PennyLane-0.17.0.dev0)
- default.qubit (PennyLane-0.17.0.dev0)
- default.qubit.autograd (PennyLane-0.17.0.dev0)
- default.qubit.jax (PennyLane-0.17.0.dev0)
- default.qubit.tf (PennyLane-0.17.0.dev0)
- default.tensor (PennyLane-0.17.0.dev0)
- default.tensor.tf (PennyLane-0.17.0.dev0)
```

* *Potential solution:*
[HIDDEN]

### Additional contract requirements

Calling the adjoint of a controlled operation outside an active tape context must produce an adjointed controlled operation while preserving its control wires.
