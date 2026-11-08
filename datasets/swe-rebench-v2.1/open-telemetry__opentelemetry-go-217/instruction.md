Suggestion: core.Key should be a type alias instead of struct
Making [`core.Key`](https://github.com/open-telemetry/opentelemetry-go/blob/e0eccc9a57e0cae76c1c5b0dde747bb79a8f1300/api/core/key.go#L8-L10) a type alias for `string` instead of a whole struct would (arguably!) make it easier to use, while still allowing us to add methods on `Key`.

### Additional contract requirements

- `core.Key` is a distinct, defined type with underlying type `string`, not a Go type alias for `string`, so it can support methods. A `core.Key` value is created by converting a `string` (for example, `core.Key("name")`), and the underlying string is the key name.
- In package `go.opentelemetry.io/api/key`, add convenience constructors that take a key name and a value and return a `core.KeyValue` whose `Key` is the given name and whose `Value` carries the corresponding type:
  - `Bool(k string, v bool) core.KeyValue` with a `BOOL` value.
  - `Int64(k string, v int64) core.KeyValue` with an `INT64` value.
  - `Uint64(k string, v uint64) core.KeyValue` with a `UINT64` value.
  - `Float64(k string, v float64) core.KeyValue` with a `FLOAT64` value.
  - `Int32(k string, v int32) core.KeyValue` with an `INT32` value.
  - `Uint32(k string, v uint32) core.KeyValue` with a `UINT32` value.
  - `Float32(k string, v float32) core.KeyValue` with a `FLOAT32` value.
  - `Bytes(k string, v []byte) core.KeyValue` with a `BYTES` value.
  - `Int(k string, v int) core.KeyValue` with an `INT32` or `INT64` value depending on word size.
  - `Uint(k string, v uint) core.KeyValue` with a `UINT32` or `UINT64` value depending on word size.
