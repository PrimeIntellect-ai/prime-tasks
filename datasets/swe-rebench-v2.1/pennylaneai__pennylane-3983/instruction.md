[BUG] Composite operator parameters are not trainable
### Expected behavior

The parameters of composite ops are trainable (just like the 1st-generation Tensor and Hamiltonians).

### Actual behavior

They are not trainable.

### Additional information

This is because composite operators put their parameters in vanilla python lists, and those are considered not trainable. My code snippet first shows a full example (mimicking [how pennylane currently sets trainable parameters](https://github.com/PennyLaneAI/pennylane/blob/601c5ca6f5caec9c917c2c57fb5b61f6ed5f4ffa/pennylane/interfaces/autograd.py#L72-L73)), and then a minimal demonstration of what we currently consider trainable.

### Source code

```shell
dev = qml.device("default.qubit", wires=2)
@qml.qnode(dev)
def circuit():
    return qml.expval(qml.prod(qml.PauliX(0), qml.RX(qnp.array(1.1), 1)))

circuit()
params = circuit.tape.get_parameters(trainable_only=False)
print(params, qml.math.get_trainable_indices(params))
# [[], [tensor(1.1, requires_grad=True)]] set()


### Minimal demo of why it doesn't work
from pennylane.math import requires_grad; from pennylane import numpy as np
print(requires_grad(np.array(1)), requires_grad([np.array(1)]))
# True False
```


### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.30.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /Users/matthews/.pyenv/versions/3.9.13/envs/pl/lib/python3.9/site-packages
Editable project location: /Users/matthews/src/github.com/PennyLaneAI/pennylane
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           macOS-13.2.1-arm64-arm-64bit
Python version:          3.9.13
Numpy version:           1.23.5
Scipy version:           1.10.0
Installed devices:
- default.gaussian (PennyLane-0.30.0.dev0)
- default.mixed (PennyLane-0.30.0.dev0)
- default.qubit (PennyLane-0.30.0.dev0)
- default.qubit.autograd (PennyLane-0.30.0.dev0)
- default.qubit.jax (PennyLane-0.30.0.dev0)
- default.qubit.tf (PennyLane-0.30.0.dev0)
- default.qubit.torch (PennyLane-0.30.0.dev0)
- default.qutrit (PennyLane-0.30.0.dev0)
- null.qubit (PennyLane-0.30.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.29.0.dev11)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
