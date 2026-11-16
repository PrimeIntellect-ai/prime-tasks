Implement ExactSizeIterator for CircularTupleWindows
`.circular_tuple_windows()` will produce the same amount of elements as the upstream iterator, so I believe the implementation should be pretty simple.

Speaking about the practical example, I want to convert a vector of 2D points to pairs of normalized vectors.

```rust
  let vecs = shape
    .into_iter()
    .circular_tuple_windows::<(_, _)>()
    .map(|((x1, y1), (x2, y2)): (Point, Point)| (x2 - x1, y2 - y1) as Point)
    .circular_tuple_windows(); //  trait `ExactSizeIterator` is not satisfied
```

### Additional contract requirements

- `Itertools::circular_tuple_windows::<U>(self) -> CircularTupleWindows<Self, U>` is available when the source iterator is an `ExactSizeIterator` and `Clone`. The returned `CircularTupleWindows` implements `ExactSizeIterator`, and its `len()` and `size_hint()` report exactly the number of elements of the source iterator.
