SparsePauliOp casting of coeffs causes errors for dtype=real
### Environment

- **Qiskit Terra version**: 0.22
- **Python version**: All
- **Operating system**: All

### What is happening?

The current init for `SparsePauliOp` has handling for storing coefficient arrays using their input dtype, [HIDDEN]. This can cause errors if the dtype is not complex.

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

I suspect this support was added in the first place to handle object arrays for parameters, and I think that should still be supported [HIDDEN]

### Additional contract requirements

- Real-valued coefficients must retain any complex Pauli phase required by an operation. In the stated example, `X.dot(Y)` must yield `Z` with coefficient `0.+1.j`.
- Object-array coefficients used for parameters must remain supported.
