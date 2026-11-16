marginal_distribution raises for NumPy array indices
### Environment

- **Qiskit Terra version**: 0.21
- **Python version**: 3.10
- **Operating system**: osx


### What is happening?

`marginal_distribution` raises error when passes a NumPy array of indices:

```python

marginal_distribution(counts, np.asarray([0, 2]))
```


--> 225 if indices is not None and ([HIDDEN] or not set(indices).issubset(range(num_clbits))):
    226     raise QiskitError(f"indices must be in range [0, {num_clbits - 1}].")
    228 if isinstance(counts, Counts):

ValueError: The truth value of an array with more than one element is ambiguous. Use a.any() or a.all()


### How can we reproduce the issue?

Try above

### What should happen?

It should work for both lists and arrays.

### Any suggestions?

_No response_

### Additional contract requirements

- `marginal_distribution` must accept NumPy arrays of valid indices and return the same marginal distribution as it does for an equivalent list of indices.
