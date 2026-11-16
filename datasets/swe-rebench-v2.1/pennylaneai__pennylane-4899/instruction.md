[BUG] `qml.ctrl` does not modify `parameter_frequencies` correctly
### Expected behavior

`qml.ctrl(op)` can be differentiated with the parameter-shift rule if `op` can be differentiated with the parameter-shift rule.
The differentiation yields the correct derivative.

### Actual behavior

The differentiation of `qml.ctrl(op)` will be wrong whenever the generator of the original op is a `SparseHamiltonian` and has more than 1 eigenvalue.


### Additional information

[HIDDEN]

### Source code

```shell
>>> @qml.qnode(qml.device("default.qubit"))
>>> def circuit(x):
...     qml.Hadamard(0)
...     qml.Hadamard(1)
...     qml.Hadamard(2)
...     qml.ctrl(qml.DoubleExcitationMinus(x, [1, 2, 3, 4]), 0)
...     return qml.expval(qml.dot([1, 1], [qml.PauliY(0), qml.PauliZ(3)]))

>>> x = pnp.array(0.7, requires_grad=True)
>>> circuit(x)
>>> print(qml.grad(circuit)(x))
>>> print(qml.gradients.param_shift(circuit)(x))

-0.43279197822247817
-0.3522647673177669
```


### Tracebacks

_No response_

### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
