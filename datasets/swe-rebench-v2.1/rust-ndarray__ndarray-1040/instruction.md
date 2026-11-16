Efficiently map array to a (possibly) different type
[`ArrayBase::mapv_into()`](https://docs.rs/ndarray/0.15.3/ndarray/struct.ArrayBase.html#method.mapv_into) consumes self and reuses its memory allocation to compute a new array with the same shape and type.  Avoiding unnecessary allocations is important when mapping very large arrays.

When writing generic methods, it is often necessary to assume that two arrays may be of different types even though we might expect them to be the same type most of the time.  For example, a method that is generic over complex numbers may be called with all real arguments, all complex arguments, or a mixture of real and complex arguments.  This precludes direct use of `mapv_into()` since we cannot assume the arguments are the same type.

Would it be worth adding something like this [`trans_mapv_into()`](https://gist.github.com/benkay86/b9f3eea271999eccf158bfbbcd30b70e), which maps an array with elements of one type to a (possibly) different type?  [HIDDEN]

### Additional contract requirements

- Expose the consuming mapping operation as `ArrayBase::mapv_into_any`.
- The mapping operation consumes its input and produces an array with the same shape.
- Mapping to a different element type must work for valid arrays with nonstandard memory layouts as well as standard layouts.
- When the input and output element types match, the input allocation is reused. Mapping to a different element type remains supported even when that requires another allocation.
