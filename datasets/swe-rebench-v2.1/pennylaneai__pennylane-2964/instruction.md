Add sparse matrix representations for Pauli Operators
While the Pauli operators (`PauliX`, `PauliY`, `PauliZ`, `Identity`) themselves are fairly dense, they are often multiplied together to form large tensors. To assist with the formation of sparse matrices for large combination operations, we should add sparse matrices for the basic Pauli operators.

Following Issue #2881, these `compute_sparse_matrix` methods should accept a `format` keyword.

### Additional contract requirements

- The `Hadamard` operator must also provide a sparse matrix representation.
- `Operator.sparse_matrix()` must return a `scipy.sparse.csr_matrix` by default.
