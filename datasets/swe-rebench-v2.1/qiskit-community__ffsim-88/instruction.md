add return_lower_ranks argument to rdm
For example, the function `make_rdm12s` from pyscf returns not only the 2-RDM but also the 1-RDM. Currently, we just discard the 1-RDM. If `ffsim.rdm` is called with `return_lower_ranks=True`, then it should return all of the RDMs up to the given rank, not just the single one.

### Additional contract requirements

- `ffsim.rdm` accepts a keyword argument `return_lower_ranks` with default value `True`.
- With `return_lower_ranks=True` and `rank=2`, the return value is a tuple `(rdm1, rdm2)` containing the 1-RDM followed by the 2-RDM.
- With `return_lower_ranks=True` and `rank=1`, the return value is a single ndarray (the 1-RDM); there are no lower ranks to return.
- With `return_lower_ranks=False`, the return value is a single ndarray for the requested rank.
