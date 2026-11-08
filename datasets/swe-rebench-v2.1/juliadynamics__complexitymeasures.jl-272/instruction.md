Lempel–Ziv complexity measure
New complexity measure:

https://en.wikipedia.org/wiki/Lempel%E2%80%93Ziv_complexity

The wiki website also has an implementation. This is really easy to implement as far as I can tell from the algorithm section at the end.

### Additional contract requirements

Expose the Lempel–Ziv 1976 measure as `LempelZiv76()`, usable with `complexity(estimator, sequence)`. For a binary sequence, `complexity` returns the number of distinct subsequences found by the linked Lempel–Ziv algorithm.
