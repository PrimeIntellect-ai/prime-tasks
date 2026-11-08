SparsePauliOp casting of coeffs causes errors for dtype=real
### Environment

- **Qiskit Terra version**: 0.22
- **Python version**: All
- **Operating system**: All

### What is happening?

The current init for `SparsePauliOp` has handling for storing coefficient arrays using their input dtype, [HIDDEN] This can cause errors if the dtype is not complex.

### How can we reproduce the issue?

Here is an example which gives an incorrect answer:
```python
# Initialize ops, with coeffs with dtype double
a = SparsePauliOp(['X'], np.array([1]))
b = SparsePauliOp(['Y'], np.array([1]))
a.dot(b)
```
This raises a warning
```
# Raises waring
.../sparse_pauli_op.py:131: ComplexWarning: Casting complex values to real discards the imaginary part
  [HIDDEN]
```
and returns the incorrect value
```
SparsePauliOp(['Z'],
              coeffs=[0])
```

### What should happen?

For the above example the correct answer should be
```
SparsePauliOp(['Z'],
              coeffs=[0.+1.j])
```

### Any suggestions?

[HIDDEN]

I suspect this support was added in the first place to handle object arrays for parameters, and I think that should still be supported if the dtype arg is not used since the asarray should default to an object array in that case.

### Additional contract requirements

- When multiplying Pauli operators with real-valued coefficients, preserve any imaginary phase introduced by the product; in particular, multiplying X by Y with unit coefficients must yield iZ.
- Multiplication must continue to support object-dtype coefficients representing circuit parameters, preserving their parameter dependence in the resulting coefficients.
