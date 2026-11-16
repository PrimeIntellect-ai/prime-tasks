feature: Add decoding option to be more strict than encoding/json: fail on CBOR map if destination struct field is not found
Currently any unknown fields are skipped during decoding, would it be possible to have an option to fail instead?

### Additional contract requirements

- Add a decoding option field `ExtraReturnErrors` of type `int` on `DecOptions`. It is a bit set of `ExtraDecErrorCond` values.
- Add a public constant `ExtraDecErrorUnknownField` (an `ExtraDecErrorCond` value) that selects the error condition when a CBOR map key does not match a field of the destination Go struct. It only affects decoding CBOR maps to Go struct values.
- `DecOptions.DecMode()` returns `(DecMode, error)`. For `ExtraReturnErrors` value 3, `DecMode()` returns an error whose `Error()` is exactly `cbor: invalid ExtraReturnErrors 3`.
- When unknown-field errors are enabled, the error message contains `cbor: found unknown field at map element index N`, where N is the zero-based map element index of the unknown field.
- `DecMode.Unmarshal(data []byte, v interface{}) error` decodes CBOR data into the supplied Go value respecting the DecMode's options.
- `DecMode.NewDecoder(r io.Reader) *Decoder` creates a decoder bound to the reader; `Decoder.Decode(v interface{}) error` reads the next CBOR value and applies the same validation rules as `DecMode.Unmarshal`.
- `DecMode.DecOptions()` returns the `DecOptions` used to create the `DecMode`, including `ExtraReturnErrors`.
