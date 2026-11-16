[BUG] Wrong expectation value of Hamiltonian with return qml.expval(H)
### Expected behavior

Expected to get the same expectation value of a qml.Hamiltonian no matter
1. how the operators and  the corresponding coefficient are ordered when it was constructed.
2. applied the grouping method ('QWC') or not.

### Actual behavior

When the below conditions are satisfied, the expectation value will not take the value (coefficient) of qml.Identity into account.
1. There is a "grouping_type" argument when qml.Hamiltonian is constructed.
2. The operator list is not  in the order of qubit number.

Example
`H_disordered = qml.Hamiltonian([1.0, 1.0, 1.0], [qml.PauliZ(1), qml.PauliZ(0), qml.Identity(0)], grouping_type='QWC')`
The list of operator is disordered in terms of qubit number.
However its expectation value differs with the value of qml.Identity from an ordered Hamiltonian
`H_ordered = qml.Hamiltonian([1.0, 1.0, 1.0], [qml.Identity(0), qml.PauliZ(0), qml.PauliZ(1)], grouping_type='QWC')`


### Additional information

_No response_

### Source code

```shell
import pennylane as qml

dev = qml.device("default.qubit", wires=2, shots=1000)
@qml.qnode(dev)
def circuit():
    return qml.expval(H)

H = qml.Hamiltonian([1.0, 1.0, 1.0], [qml.PauliZ(0), qml.PauliZ(1), qml.Identity(0)], grouping_type='QWC')
print(circuit())

H = qml.Hamiltonian([1.0, 1.0, 1.0], [qml.PauliZ(1), qml.PauliZ(0), qml.Identity(0)], grouping_type='QWC')
print(circuit())

H = qml.Hamiltonian([1.0, 1.0, 1.0], [qml.PauliZ(1), qml.PauliZ(0), qml.Identity(0)], grouping_type='commuting')
print(circuit())

H = qml.Hamiltonian([1.0, 1.0, 1.0], [qml.PauliZ(1), qml.PauliZ(0), qml.Identity(0)])
print(circuit())
```


### Tracebacks

_No response_

### System information

```shell
Platform info:           macOS-13.0.1-arm64-arm-64bit
Python version:          3.9.12
Numpy version:           1.23.3
Scipy version:           1.9.3
Installed devices:
- default.gaussian (PennyLane-0.30.0)
- default.mixed (PennyLane-0.30.0)
- default.qubit (PennyLane-0.30.0)
- default.qubit.autograd (PennyLane-0.30.0)
- default.qubit.jax (PennyLane-0.30.0)
- default.qubit.tf (PennyLane-0.30.0)
- default.qubit.torch (PennyLane-0.30.0)
- default.qutrit (PennyLane-0.30.0)
- null.qubit (PennyLane-0.30.0)
- lightning.qubit (PennyLane-Lightning-0.30.0)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- `qml.pauli.are_identical_pauli_words(pauli_1, pauli_2)` is a public function in `pennylane/pauli/utils.py` that returns a boolean indicating whether two operators represent the same Pauli word. It must return `True` whenever both inputs are `qml.Identity` operators, regardless of the wire labels they act on.
- When a `qml.Hamiltonian` is constructed with a `grouping_type`, it exposes a public `grouping_indices` attribute: a list of lists of integer indices describing the groups of terms produced by the selected grouping algorithm. The indices must include identity terms even when the wire ordering is non-standard.
- A Hamiltonian expectation value includes the coefficient-weighted contribution of every Identity term.
