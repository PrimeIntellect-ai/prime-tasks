eig for one-dimension matrix
The returns of `eig` function are inconsistent with document when matrix.rows = 1.
```
A = mpmath.matrix(1)
print(mpmath.eig(A, left=False, right=False))
```
This code returns `([mpf('1.0')], matrix([['1.0']]))`

### Additional contract requirements

- For a 1×1 matrix, when `eig` is called with `left=False` and `right=False`, it should return only the eigenvalues, not a tuple containing an eigenvector matrix.
