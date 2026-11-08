[BUG] `Controlled.has_sparse_matrix` is incorrect for ops without matrices or sparse matrices
### Expected behavior

`Operator.has_sparse_matrix` should agree with whether or not an actual matrix is returned by `Operator.sparse_matrix`

### Actual behavior

`Controlled.has_sparse_matrix` is always true.

### Additional information

_No response_

### Source code

```shell
>>> op = qml.ctrl(qml.Permute(np.array([1, 0, 2]), (0,1, 2)), (3,4))
>>> op.has_sparse_matrix
True
```

### Tracebacks

```shell

```

### System information

```shell
master
```

### Existing GitHub issues

- [x] I have searched existing GitHub issues to make sure the issue does not already exist.
