gram_schmidt doesn't return the R matrix
Currently, `gram_schmidt` only returns the Q matrix. The R matrix is used in the [shift selection for the LRADI method](https://github.com/pymor/pymor/blob/1aeccb428700fa140cb6faa7490bdaf87a9754a3/src/pymor/algorithms/lyapunov.py#L285-L287) and in the [rational Krylov subspace method for Lyapunov equations](http://www.dm.unibo.it/~simoncin/rksm.m) (related to #387).

It might also be useful for computing an SVD of a vectorarray (Q * svd(R)).

### Additional contract requirements

Callers can pass `return_R=True` to `gram_schmidt` to receive `(Q, R)` instead of only `Q`. The returned factors must represent the orthogonalization: the input vectors are reconstructed from `Q` using the coefficients in `R` (up to numerical precision and any vectors discarded as numerically dependent). Calls that do not request `R` continue to return only the orthogonalized vector array.
