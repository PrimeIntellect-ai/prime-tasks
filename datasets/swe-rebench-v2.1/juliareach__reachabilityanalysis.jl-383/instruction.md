Fix type piracy for "set" wrt LazySets
Required fixes:

- [x] set
- [x] array (eg. when using a CPA)

### Additional contract requirements

- After the fix, `set` and `array` are the LazySets functions of the same name,
  so they also dispatch to LazySets methods for LazySets types: for example,
  `set(LinearMap(M, X))` returns `X`, and `array` of a `CartesianProductArray`
  returns the array of sets it stores.
