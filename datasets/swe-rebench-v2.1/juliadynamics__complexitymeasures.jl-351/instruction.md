Pretty printing for `Counts` and `Probabilities`
In #341, I remove the dependency on DimensionalData.jl. The result is that we lose pretty printing of the marginals (outcomes) for `Counts` and `Probabilities`. We should implement pretty printing manually here.

### Additional contract requirements

- The `text/plain` representation of a one-dimensional `Counts{T,1}` or `Probabilities{T,1}` begins with a line of the form `<Name>{<T>,1} over <N> outcomes`, where `<Name>` is `Counts` or `Probabilities` and `<N> = length(A)`.
- The `text/plain` representation of a `Counts{T,N}` or `Probabilities{T,N}` with `N ≥ 2` begins with a line of the form `<d1>×<d2>×…×<dN> <Name>{<T>,N}`, where `<di> = size(A, i)`.
- The `text/plain` representation displays the array's data values alongside the outcome labels (marginals) for the displayed dimensions.
- For `N ≥ 3`, the `text/plain` representation shows a two-dimensional slice of the data; when more than one slice exists, it ends with a line of the form `[and <M> more slices...]`, where `<M>` is the number of remaining slices.
