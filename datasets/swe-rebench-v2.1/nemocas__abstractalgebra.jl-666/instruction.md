lu does not work for matrices with fewer columns than rows
For example the following makes an access to an undefined reference:

```
using AbstractAlgebra
R = GF(7)
m = 20
n = 10
S = MatrixSpace(R, m, n)
A = rand(S)
r, P, L, U = lu(A)
P*A == L*U
```

The corresponding function in Flint works for all dimensions.
