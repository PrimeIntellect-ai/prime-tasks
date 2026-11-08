[BUG] The `_controlled` method of `DiagonalQubitUnitary` returns the wrong operation
### Expected behavior

`DiagonalQubitUnitary(D, wires=wires)._controlled(control=control)` queues the controlled version of the `DiagonalQubitUnitary`, controlled by the wires `control`, which should again be a `DiagonalQubitUnitary` with matrix dimension `2**(len(wires)+len(control))`.

### Actual behavior

`DiagonalQubitUnitary(D, wires=wires)._controlled(control=control)` queues a `DiagonalQubitUnitary` with diagonal `np.array([1, 1, *D])`, which in particular has the incorrect shape (except for the case of `len(D)=2`):
```python
O = qml.DiagonalQubitUnitary([-1, -1, -1, -1], wires=[0, 1])
with qml.tape.QuantumTape() as tape:
    O._controlled(control=2)
ctrl_O = tape.operations[0]
```
```pycon
>>> ctrl_O.get_matrix().shape
(6, 6)
>>> qml.math.diag(ctrl_O.get_matrix())
array([ 1,  1, -1, -1, -1, -1])
```

### Additional information

It is clear why this is happening:
```python
def _controlled(self, control):
    DiagonalQubitUnitary(
        [HIDDEN]
        wires=Wires(control) + self.wires,
   )
```
[HIDDEN]

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Not relevant, bug source was found in source code.
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- The controlled operation is a `DiagonalQubitUnitary` acting on the combined wire set `Wires(control) + self.wires`, so the control wire precedes the original wires.
- The controlled operation acts as the identity when the control is inactive and applies the original diagonal unitary when the control is active.
