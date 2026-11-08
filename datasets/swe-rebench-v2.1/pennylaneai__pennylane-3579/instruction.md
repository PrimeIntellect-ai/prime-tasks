[BUG] `metric_tensor` does not take `qml.adjoint` correctly into account
### Expected behavior

The transform `metric_tensor` respects the `qml.adjoint` transform.

### Actual behavior

In the following example, the `adjoint` of one particular operation in the circuit is realized in three ways:
1. Via classical preprocessing of the rotation angle, corresponding to inversion.
2. Via the deprecated in-place inversion, yielding the same metric tensor as 1.
3. Via `qml.adjoint`, yielding a differing metric tensor.

```python
dev = qml.device("default.qubit", wires=3)

@qml.qnode(dev, interface="jax")
def circuit(x):
    qml.RX(x[0], wires=0)
    qml.CNOT([0, 1])
    qml.RZ(0.4, wires=1)
    qml.CNOT([0, 1])
    qml.RX(x[0], wires=0)
#     qml.RZ(-x[1], wires=0) # Produces the correct MT via preprocessing
#     qml.RZ(x[1], wires=0).inv() # Produces the correct MT
#     qml.adjoint(qml.RZ)(x[1], wires=0) # Produces the wrong MT
    return qml.expval(qml.PauliZ(0))

x = pnp.array([0.543, 0.352], requires_grad = True)
y = pnp.array(-0.654, requires_grad = True)

print(qml.transforms.metric_tensor(circuit)(x))
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
Version: 0.28.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/david/venvs/xenv/lib/python3.10/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning

Platform info:           Linux-5.15.0-56-generic-x86_64-with-glibc2.35
Python version:          3.10.6
Numpy version:           1.23.4
Scipy version:           1.9.3
Installed devices:
- default.gaussian (PennyLane-0.28.0.dev0)
- default.mixed (PennyLane-0.28.0.dev0)
- default.qubit (PennyLane-0.28.0.dev0)
- default.qubit.autograd (PennyLane-0.28.0.dev0)
- default.qubit.jax (PennyLane-0.28.0.dev0)
- default.qubit.tf (PennyLane-0.28.0.dev0)
- default.qubit.torch (PennyLane-0.28.0.dev0)
- default.qutrit (PennyLane-0.28.0.dev0)
- null.qubit (PennyLane-0.28.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.27.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
