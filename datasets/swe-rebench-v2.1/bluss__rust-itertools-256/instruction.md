izip!(): [HIDDEN] if there are only two input parameters
Currently, `izip!()` always uses a map. It's redundant when we only have two input parameters.

Use simpler type or use more consistent type? The map closure's type is always anonymous anyway, so it can't be used for much.

### Additional contract requirements

With exactly two inputs, `izip!` returns the standard iterator `Zip` type, equivalent to zipping the first iterator with the second and without an additional mapping adaptor. With more than two inputs, it continues to yield tuples containing one item from each input and stops when any input is exhausted.
