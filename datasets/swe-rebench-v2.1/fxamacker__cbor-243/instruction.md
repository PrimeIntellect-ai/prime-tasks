Properly handle empty values for custom types
Currently using `omitempty` with custom types doesn't work correctly due to [it being hardcoded](https://github.com/fxamacker/cbor/blob/bffaf0cda7c548af6e819cd5385f025bb6fee6f8/encode.go#L1329-L1345). For example, empty structs are still encoded as empty maps instead of omitting the field and fields for types implementing `encoding.BinaryMarshaler` are still included even when `MarshalBinary` returns an empty `[]byte`.

It seems that the `isEmptyValue` was copied from `encoding/json` but it behaving this way really makes it harder to support more compact encodings.

It would be great if one could override empty value handling for custom types or if existing empty value handling would behave correctly at least for the above two cases (empty structs and types implementing `encoding.BinaryMarshaler`).

### Additional contract requirements

- For zero-valued `time.Time` and `big.Int` struct fields, `omitempty` is a no-op: they remain encoded, respectively, as `[]byte{0xa1, 0x61, 0x74, 0xf6}` for field `t` and `[]byte{0xa1, 0x62, 0x62, 0x69, 0xc2, 0x40}` for field `bi`.
