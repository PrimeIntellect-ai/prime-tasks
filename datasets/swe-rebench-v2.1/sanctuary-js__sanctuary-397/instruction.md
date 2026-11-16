Add S.sort and S.sortBy
Add Sanctuary version of [R.sort](http://ramdajs.com/0.23.0/docs/#sort) and [R.sortBy](http://ramdajs.com/0.23.0/docs/#sort).

### Additional contract requirements

- Add a public function `S.sort` with signature `sort :: (Ord a, Applicative m, Foldable m, Monoid m) => m a -> m a`. Its `toString()` value must be exactly `sort :: (Ord a, Applicative m, Foldable m, Monoid m) => m a -> m a`.
- Add a public function `S.sortBy` with signature `sortBy :: (Ord b, Applicative m, Foldable m, Monoid m) => (a -> b) -> m a -> m a`. Its `toString()` value must be exactly `sortBy :: (Ord b, Applicative m, Foldable m, Monoid m) => (a -> b) -> m a -> m a`.
- `S.sort(m)` returns a structure of the same type as `m` containing the same elements in non-decreasing order according to `Z.lte`. The sort is stable: elements that compare equal preserve their original relative order. If `m` is empty, the result is the empty value of its constructor.
- `S.sortBy(f, m)` returns a structure of the same type as `m` containing the same elements ordered by the keys produced by applying `f` to each element, comparing keys with `Z.lte`. The sort is stable: elements whose keys compare equal preserve their original relative order. If `m` is empty, the result is the empty value of its constructor.
- `m` may be any structure satisfying the Applicative, Foldable and Monoid constraints, not only arrays.
