Generate negative indices from the `slices()` strategy
For example, `slices(size=3)` should be able to generate `slice(-3, -1)` as an equivalent form of `slice(0, 2)`.  We should also sometimes draw `step=None` if `step=1` would be allowed.  It would also be nice to support slicing length-zero sequences, i.e. `[HIDDEN])`.

Both would be helpful for downstream users - see e.g. https://github.com/Quansight/ndindex/issues/46.

### Additional contract requirements

- For `slices(size=0)`, generated slices must have a nonzero step or `None`, and applying them to an empty sequence must yield an empty sequence.
