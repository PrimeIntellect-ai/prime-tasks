Implement Clone for CircularTupleWindows
The current implementation of `CircularTupleWindows` uses [HIDDEN], which already requires the underlying iterator implement `Clone`, so this is a simple addition.

### Additional contract requirements

- `CircularTupleWindows<I, T>` must implement `Clone` whenever `I: Clone` and `T: Clone`. Cloning produces an independent iterator that continues from the same position in the cycle as the original, so the clone and the original yield the same remaining items.
- The public adaptor `Itertools::circular_tuple_windows(self) -> CircularTupleWindows<Self, T>` yields overlapping circular tuples of the requested tuple type `T`.
