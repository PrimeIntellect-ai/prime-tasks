Add `rng` argument to `TransferOperator` and the underlying functions -
It would be nice to have a perfectly reproducible transfer operator and invariant measure for `TransferOperator`. When estimating the invariant measure, we apply the approximated transfer operator to a random distribution. This random distribution should accept an `rng` argument. Ref #337

### Additional contract requirements

The direct data-and-binning entry point `invariantmeasure(data, binning; rng=...)` must accept and use a caller-supplied RNG for the random initialization of the invariant-measure estimate. Repeating the call with the same initial RNG state must produce reproducible probabilities.
