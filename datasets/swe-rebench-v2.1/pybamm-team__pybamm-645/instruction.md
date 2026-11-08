set relative and absolute tolerances separately for solver
At the moment we use the same tol for both. Would be good to have additional control over these. Also, the defaults are pretty tight so we might relax them a bit to get a good balance of speed and accuracy.

### Additional contract requirements

Solver constructors must let callers provide relative and absolute tolerances independently using `rtol` and `atol`; the solver must retain and apply those values independently during integration. Both tolerances may also be adjusted independently after construction. The default relative and absolute tolerances should be relaxed compared with the former shared default of `1e-8`; no particular replacement value is required.
