Add matrix support for fermionic objects
### Feature details

⚠️ This issue is part of an internal assignment and not meant for external contributors.

The [fermi](https://docs.pennylane.ai/en/stable/code/qml_fermi.html) module has several functions and classes for creating and manipulating fermionic operators. It will be useful to have tools for obtaining the matrix representation of these operators. The [FermiWord](https://docs.pennylane.ai/en/stable/code/api/pennylane.fermi.FermiWord.html) and [FermiSentence](https://docs.pennylane.ai/en/stable/code/api/pennylane.fermi.FermiSentence.html) objects can be upgraded to have a `to_mat()` method that allows computing their matrix representation, similar to the `PauliWord` and `PauliSentence` classes. The users can then compute the matrix as

```
>>> import pennylane as qml
>>> op = qml.fermi.FermiWord({(0, 0): '+', (1, 1): '-'})
>>> op.to_mat()
array([[0.+0.j, 0.+0.j, 0.+0.j, 0.+0.j],
       [0.+0.j, 0.+0.j, 0.+0.j, 0.+0.j],
       [0.+0.j, 1.+0.j, 0.+0.j, 0.+0.j],
       [0.+0.j, 0.+0.j, 0.+0.j, 0.+0.j]])
```

### Implementation
The `to_mat()` method should be added as an instance method to `FermiWord` and `FermiSentence`. The method should have an optional keyword argument, `n`,  for specifying the total number of orbitals which determines the matrix size.

### Requirements
1. The computed matrix should properly describe the behaviour of fermionic operators.
2. The computed matrix should satisfy the commutation relationship between fermionic operators.

### Additional contract requirements

- The public keyword argument is named `n_orbitals`; the `n` mentioned in the base refers to this argument. An `n` alias is not required.
- `FermiWord.to_mat(self, n_orbitals=None)` is a public instance method of `pennylane.fermi.FermiWord`, and `FermiSentence.to_mat(self, n_orbitals=None)` is a public instance method of `pennylane.fermi.FermiSentence`.
- `n_orbitals` is an optional integer. When it is omitted, the number of orbitals is inferred from the largest orbital index present in the operator as (largest orbital index + 1). When it is supplied, it must be at least that inferred number of orbitals.
- The returned value is a NumPy `ndarray` with complex dtype whose shape is `2 ** n_orbitals` by `2 ** n_orbitals`, obtained via the Jordan-Wigner transform.
- If a supplied `n_orbitals` is smaller than the inferred number of orbitals, a `ValueError` is raised whose message contains `n_orbitals cannot be smaller than <minimum>`, where `<minimum>` is the inferred number of orbitals (for example, the message contains `n_orbitals cannot be smaller than 2` for a two-orbital operator and `n_orbitals cannot be smaller than 3` for a three-orbital operator).
