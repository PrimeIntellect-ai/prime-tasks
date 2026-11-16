fflu doesn't work for rows(A) == 1
For example:

```
using AbstractAlgebra
R = ZZ
m = 1
n = 1
rank = rand(0:min(m, n))
S = MatrixSpace(R, m, n)
A = randmat_with_rank(S, rank, -10:10)
r, d, P, L, U = fflu(A)

R2 = parent(1//one(R))
V = MatrixSpace(R2, m, m)
D = V()
if m >= 1
    D[1, 1] = 1//U[1, 1]
end
if m > 2
   for j = 1:m - 2
      D[j + 1, j + 1] = (1//U[j, j])*(1//U[j + 1, j + 1])
   end
end
if m >= 2
   D[m, m] = 1//U[m - 1, m - 1]
end
L2 = change_base_ring(R2, L)
U2 = change_base_ring(R2, U)
change_base_ring(R2, P*A) == L2*D*U2
```

### Additional contract requirements

- `fflu` must also handle a rank-zero 1×1 input without failing and report `r == 0`. The displayed inverse-based reconstruction identity applies to rank-one 1×1 inputs only; it is not defined when `U[1, 1]` is zero.
