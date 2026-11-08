[BUG] hadamard gradient does not work with wires-broadcasted measurements
### Expected behavior

I would expect `hadamard_grad` to be interchangeable with `param_shift` in cases where there is no explicit error

### Actual behavior

Output gradient is simply `array([0.])`

### Additional information

_No response_

### Source code

```shell
tape = qml.tape.QuantumScript([qml.RX(0.1, 0)], [qml.probs()])

batch, fn = qml.gradients.hadamard_grad(tape)
fn(qml.device('default.qubit').execute(batch))
```


### Tracebacks

_No response_

### System information

```shell
on master
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
