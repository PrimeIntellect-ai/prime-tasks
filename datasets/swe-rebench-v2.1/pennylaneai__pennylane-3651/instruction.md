[BUG] `SpecialUnitary` is not trainable with autodiff on `"default.mixed"` device
### Expected behavior

The following code should produce a non-vanishing gradient:

<details>
<summary>Code</summary>

```python
dev = qml.device('default.mixed', wires=1)

@qml.qnode(dev, interface="jax")
def circuit(x):
    qml.SpecialUnitary(x, wires=[0])
    return qml.expval(qml.PauliZ(0))

x = jax.numpy.array([0.2, 0.1, 0.6])
jax.grad(circuit)(x) # Should produce Array([-0.68453361, -0.3422668 ,  0.03581418], dtype=float64)
```

</details>


### Actual behavior

The above code exampe produces a vanishing gradient:

<details>
<summary>Code</summary>

```python
dev = qml.device('default.mixed', wires=1)

@qml.qnode(dev, interface="jax")
def circuit(x):
    qml.SpecialUnitary(x, wires=[0])
    return qml.expval(qml.PauliZ(0))

x = jax.numpy.array([0.2, 0.1, 0.6])
```
```pycon
>>> jax.grad(circuit)(x)
Array([0., 0., 0.], dtype=float64)
```

</details>

### Additional information

[HIDDEN]

[HIDDEN]

For other devices, we might run into trouble in the future if a custom device:
- is to be used with automatic differentiation (i.e. not with a gradient transform)
- can not handle operations that provide a matrix generically


### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Name: PennyLane
Version: 0.29.0.dev0
Summary: PennyLane is a Python quantum machine learning library by Xanadu Inc.
Home-page: https://github.com/XanaduAI/pennylane
Author:
Author-email:
License: Apache License 2.0
Location: /home/david/venvs/dev/lib/python3.10/site-packages
Requires: appdirs, autograd, autoray, cachetools, networkx, numpy, pennylane-lightning, requests, retworkx, scipy, semantic-version, toml
Required-by: PennyLane-Lightning, PennyLane-qiskit

Platform info:           Linux-5.15.0-60-generic-x86_64-with-glibc2.35
Python version:          3.10.6
Numpy version:           1.23.5
Scipy version:           1.9.3
Installed devices:
- default.gaussian (PennyLane-0.29.0.dev0)
- default.mixed (PennyLane-0.29.0.dev0)
- default.qubit (PennyLane-0.29.0.dev0)
- default.qubit.autograd (PennyLane-0.29.0.dev0)
- default.qubit.jax (PennyLane-0.29.0.dev0)
- default.qubit.tf (PennyLane-0.29.0.dev0)
- default.qubit.torch (PennyLane-0.29.0.dev0)
- default.qutrit (PennyLane-0.29.0.dev0)
- null.qubit (PennyLane-0.29.0.dev0)
- lightning.qubit (PennyLane-Lightning-0.28.2)
- qiskit.aer (PennyLane-qiskit-0.28.0)
- qiskit.basicaer (PennyLane-qiskit-0.28.0)
- qiskit.ibmq (PennyLane-qiskit-0.28.0)
- qiskit.ibmq.circuit_runner (PennyLane-qiskit-0.28.0)
- qiskit.ibmq.sampler (PennyLane-qiskit-0.28.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- The `"default.mixed"` device must support `SpecialUnitary` as a native operation, so
  that it is applied directly instead of being decomposed. Concretely,
  `qml.device("default.mixed", wires=n).supports_operation("SpecialUnitary")` must return
  `True` for any `n >= 1`.
- With `SpecialUnitary` supported natively, differentiating a QNode that uses it on
  `"default.mixed"` must yield a non-vanishing gradient (the parameters must remain
  trainable).
