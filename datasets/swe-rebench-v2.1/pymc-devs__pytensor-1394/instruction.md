lu_solve doesn't work with batched inputs
### Description

```python
import pytensor.tensor as pt
A = pt.tensor3("A")
b = pt.vector("b")

lu_and_pivots = pt.linalg.lu_factor(A)
x = pt.linalg.lu_solve(lu_and_pivots, b, b_ndim=1)  # ValueError: PivotToPermutations only works on 1-D inputs
```

We'll need to maybe use [HIDDEN], because just [HIDDEN] doesn't cut it. We may also consider [HIDDEN], [HIDDEN]

This is required for #1374

### Additional contract requirements

- `lu_solve` supports leading batch dimensions on the LU factors and right-hand side when those dimensions are broadcast-compatible. The result has the broadcast batch shape followed by the core shape of `b`.
- `b_ndim` identifies the number of core dimensions of `b`: `1` for vectors and `2` for matrices.
- Incompatible batch shapes raise `ValueError`.
