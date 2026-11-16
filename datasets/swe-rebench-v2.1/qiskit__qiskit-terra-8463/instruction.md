QuantumCircuit.initialize()  no longer accepts single instance of Qubit
### Environment

Used to work in Qiskit v0.34.2, tested to not work in v0.37. Appears to have been broken by commit https://github.com/Qiskit/qiskit-terra/commit/3591fa635db75e3d7f1afea19359acb2fb3a6740

### What is happening?

We used to be able to `circuit.initialize([0,1], qr[0])` but now that raises an error `TypeError: 'Qubit' object is not iterable`

Changing to `circuit.initialize([0,1], [qr[0]])` works as the `qubits` parameter is now a list. [HIDDEN]

### How can we reproduce the issue?

```
# Successful with Qiskit v0.34.2, raises error with v0.35.0+
qr = qiskit.QuantumRegister(1)
circuit = qiskit.circuit.QuantumCircuit(qr)
circuit.initialize([0, 1], qr[0])
```

### What should happen?

Unless there is a need to not convert single `Qubit` into a list automatically, I would have expected the `circuit.initialize([0,1], qr[0])` to work.

### Any suggestions?

It appears `QuantumCircuit._bit_argument_conversion()` still exists. [HIDDEN]

### Additional contract requirements

- `QuantumCircuit.initialize` must accept a single `Qubit` as its qubit argument and initialize it equivalently to passing that qubit in a one-element list.
