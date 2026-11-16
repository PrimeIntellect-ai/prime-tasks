Add eNotation and Base64 formatting for float* types
Using the example simpledriver in the device-service-go, I am able to use all the NewXValue methods to submit the various types of data except floats.  When I use the two NewFloatXValue methods, the values are somehow being binary encoded to that what gets submitted is a random string (examp;e:  "value":"PqRObw==")

### Additional contract requirements

- `CommandValue.ValueToString(encoding ...string)` accepts an optional float
  encoding. When the argument is `contract.Base64Encoding` (or when no argument
  is supplied, which defaults to `contract.Base64Encoding`), a `Float32` or
  `Float64` value is returned as the standard Base64 encoding of its big-endian
  byte representation (for example `AAAAAQ==` for the smallest positive
  `float32`).
- When the argument is `contract.ENotation`, a `Float32` or `Float64` value is
  returned as a scientific-notation string produced with Go's `%e` verb, i.e.
  `fmt.Sprintf("%e", value)`: six digits after the decimal point followed by a
  signed exponent (for example `1.401298e-45` for the smallest positive
  `float32`, `3.402823e+38` for the largest `float32`, `4.940656e-324` for the
  smallest positive `float64`, and `1.797693e+308` for the largest `float64`).
- For every non-float type the string returned by `ValueToString` is unchanged
  from the pre-existing behavior.
