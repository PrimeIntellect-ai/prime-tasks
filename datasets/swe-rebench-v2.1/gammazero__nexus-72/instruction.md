Floating point arguments
There is no `wamp.AsFloat64` function. That would be useful.

### Additional contract requirements

Provide `wamp.AsFloat64` following the conversion-helper convention used by the package: it returns the converted `float64` and a success boolean. It must accept `float64`, `float32`, `int64`, `wamp.ID`, `uint64`, `int`, `int32`, `uint`, and `uint32`, converting each to its corresponding floating-point value; unsupported input types must return `false` for success.
