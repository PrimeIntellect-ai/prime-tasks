Opflow adjoint of Hermitian PauliSumOp
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**:  0.16.0
- **Python version**: 3.7.3
- **Operating system**: macOS Catalina 10.15.1

### What is the current behavior?

If you create a Hermitian operator including a term with an odd number of `Y` terms as a PauliSumOp and convert it into a measurement StateFn it flips a sign where it should not. See code below.

### Steps to reproduce the problem

`test = SummedOp([(Z ^ Z), (Y ^ I)]).reduce()`
`test = ~StateFn(test)`
`test.primitive.to_pauli_op()`

gives

`SummedOp([PauliOp(Pauli('ZZ'), coeff=1.0), PauliOp(Pauli('YI'), coeff=-1.0)], coeff=1.0, abelian=False)`


The following  cases are handled correctly
for
`test = PauliOp(Pauli('YI'), coeff=1.0)`

gives
`PauliOp(Pauli('YI'), coeff=1.0)`

and for
`test =  SummedOp([(Z ^ X), (Y ^ I)])`

gives
`SummedOp([PauliOp(Pauli('YI'), coeff=1.0), PauliOp(Pauli('ZX'), coeff=1.0)], coeff=1.0, abelian=False)`

### What is the expected behavior?

It seems like the adjoint operator `~` does not implement the correct complex transpose on a PauliSumOp.

### Suggested solutions

The error seems to be somewhere in the `PauliSumOp`.
