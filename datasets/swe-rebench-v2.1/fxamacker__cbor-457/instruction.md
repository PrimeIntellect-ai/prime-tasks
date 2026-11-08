feature: `IntDecMode` value for `int64` with overflow to `*big.Int`
**Is your feature request related to a problem? Please describe.**

The duality of decoding into int64/uint64 when given an empty interface has great affinity to the CBOR data model, but in applications that predominantly model integers as int64, yet still want access to arbitrary precision integers, `IntDecConvertSigned` still leaves an awkward gap (at least from what I can infer from the documentation):

- Values in range `[math.MinInt64, math.MaxInt64]` succeed with an `int64`.
- Values in range `(math.MaxInt64, math.MaxUint64]` fail with `UnmarshalTypeError`.
- Values less than `math.MinInt64` or greater than `math.MaxUint64` succeed with a `*big.Int`.

**Describe the solution you'd like**

An additional `IntDecMode` which behaves like `IntDecConvertSigned`, except that in any case where overflowing values yield an `UnmarshalTypeError`, they instead succeed with a `*big.Int`.

**Describe alternatives you've considered**

- `IntDecConvertSigned` could be amended to have the behavior described above if it doesn't cause compatibility breakage. Since it doesn't appear that `*big.Int` support can be disabled, thus decode into `any` with arbitrary data could yield `*big.Int`, it might be rare that a compatibility breakage would arise in practice, given that the calling code would need to tolerate receiving big integers.

- Using `IntDecConvertNone` as is. This does mean that, for cases in which nearly all integer data fits in `int64` range, the calling code must deal with `int64`, `uint64`, and `*big.Int`, as well as potentially overflow-prone conversions from uint64 to int64. For such an application, this is less desirable than merely dealing with `int64` and `*big.Int` data.

### Additional contract requirements

- The mode names are `IntDecConvertSignedOrBigInt` for the requested behavior and `IntDecConvertSignedOrFail` for signed conversion that returns an `UnmarshalTypeError` when an integer does not fit in `int64`. For `IntDecConvertSignedOrFail`, the error text contains `9223372036854775808 overflows Go's int64` for `math.MaxInt64+1` and `-9223372036854775809 overflows Go's int64` for `math.MinInt64-1`.
