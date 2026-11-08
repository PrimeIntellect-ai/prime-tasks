Add `is_zero_entry`
Hecke has a useful function `is_zero_entry`, and I think we should add it to AbstractAlgebra. Basic version:
```julia
is_zero_entry(M::MatrixElem, i::Int, j::Int) = [HIDDEN]
```
But other implementations can do more clever things. In particular, they may be able to avoid creating an auxiliary Julia object to represent the value of `M[i,j]`.

This can then be used as a building block for finding pivots (do we already have functions for finding the first/next/last non-zero entry in a row/column? If not, we should?)

### Additional contract requirements

- `is_zero_entry(M::MatrixElem, i::Int, j::Int)` must return `true` when the entry at row `i`, column `j` is zero, and `false` otherwise.
