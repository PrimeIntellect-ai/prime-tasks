Floating Point Precision
I can understand why  `-1`  was used [here](https://github.com/rs/zerolog/blob/9070d49a1a4154c819e9c5ae6c923f3cc916d959/internal/json/types.go#LL314C44-L314C44), but it can cause some pain when loading the message, say in elasticsearch with the value `0` instead of `0.00` for example.

For me, it creates a field of type `long` instead of what I really want it to be, a `float` and I'm sure there may be other specific cases.

I propose adding a `FloatingPointPrecission` variable somewhere around [here](https://github.com/rs/zerolog/blob/9070d49a1a4154c819e9c5ae6c923f3cc916d959/globals.go#L110) with a default value of `-1`, then everyone is happy :)

### Additional contract requirements

- Add a public variable `FloatingPointPrecision` in package `zerolog` (module `github.com/rs/zerolog`) with a default value of `-1`. When it is set to a value other than `-1`, it controls the number of digits after the decimal point used when formatting floating-point numbers in JSON output; when it is `-1`, the existing default formatting is used. It applies to floating-point values written through the public logging API (for example `Float32`, `Float64`, `Floats32`, `Floats64`, `Dur`, `Durs`).
- Add a `precision int` parameter to the JSON encoder methods in package `github.com/rs/zerolog/internal/json`:
  - `func (Encoder) AppendFloat32(dst []byte, val float32, precision int) []byte`
  - `func (Encoder) AppendFloat64(dst []byte, val float64, precision int) []byte`
  - `func (Encoder) AppendFloats32(dst []byte, vals []float32, precision int) []byte`
  - `func (Encoder) AppendFloats64(dst []byte, vals []float64, precision int) []byte`
  - `func (Encoder) AppendDuration(dst []byte, d time.Duration, unit time.Duration, useInt bool, precision int) []byte`
  - `func (Encoder) AppendDurations(dst []byte, vals []time.Duration, unit time.Duration, useInt bool, precision int) []byte`

  When `precision` is `-1` the existing default formatting is used; otherwise the value is formatted with that many digits after the decimal point. `AppendFloats32`/`AppendFloats64` encode a JSON array of the formatted values, and `AppendDuration`/`AppendDurations` encode the duration(s) as an integer when `useInt` is true and as a formatted float otherwise.
- Add a `precision int` parameter to the CBOR encoder methods in package `github.com/rs/zerolog/internal/cbor`:
  - `func (Encoder) AppendFloat32(dst []byte, val float32, precision int) []byte`
  - `func (Encoder) AppendFloat64(dst []byte, val float64, precision int) []byte`
