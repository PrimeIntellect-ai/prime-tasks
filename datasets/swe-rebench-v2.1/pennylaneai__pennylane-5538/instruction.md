[BUG] `qml.equal` does not work with `qml.HilbertSchmidt`
### Expected behavior

Equal ops are detected to be equal

### Actual behavior

Equal ops are reported to be different

### Additional information

The culprit is `v_tape` in the hyperparameters.

### Source code

```shell
u_tape = qml.tape.QuantumScript([qml.Hadamard(0)])
v_function = lambda params: qml.RZ(params[0], wires=1)
v_params = np.array([0.6])
op1 = qml.HilbertSchmidt(v_params, v_wires=[1], u_tape=u_tape, v_function=v_function)
op2 = qml.HilbertSchmidt(v_params, v_wires=[1], u_tape=u_tape, v_function=v_function)

qml.equal(op1, op2)
```


### Tracebacks

```shell
False
```


### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
