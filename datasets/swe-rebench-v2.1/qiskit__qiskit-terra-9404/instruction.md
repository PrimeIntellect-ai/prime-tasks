TensoredOp's to_matrix() returns a wrong value if coeff is not 1
### Environment

- **Qiskit Terra version**:
  0.22.4
- **Python version**:
  3.10.4
- **Operating system**:
  Ubuntu 20.04.5 LTS


### What is happening?

`TensoredOp`'s `to_matrix()` returns a wrong value if coeff is not 1.

### How can we reproduce the issue?

Run the following code:
```
from qiskit.opflow import Plus, Zero
print((0.5 * (Plus ^ Zero)).to_matrix())
```

Then, the following will be printed:
```
[0.1767767+0.j 0.       +0.j 0.1767767+0.j 0.       +0.j]
```


### What should happen?

The following should be printed:
```
[0.35355339+0.j, 0.        +0.j, 0.35355339+0.j, 0.        +0.j]
```

### Any suggestions?

I think this problem is related to #9283.

### Additional contract requirements

A tensored expression's matrix or state-vector result must reflect its global coefficient correctly: it must match the Kronecker product of its component results scaled by that coefficient. This applies to non-unit coefficients other than 0.5 as well as the coefficient-0.5 state example above.
