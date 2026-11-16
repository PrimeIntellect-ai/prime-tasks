Using `ByteSliceMode` (unreleased new feature) can encode invalid CBOR data
`ByteSliceMode` is a new feature planned for v2.7.0 (not yet released) and was added by:
- #476

Unfortunately, using the non-default encoding setting for `ByteSliceMode` can produce invalid CBOR data in some edge cases.

This problem was discovered by fuzzing.

### Reproducer

Steps:
- Create an encoding mode with `ByteSliceMode` set to any non-default option
- Encode `cbor.Tag` with tag content of `[]byte` type

```Go
func main() {
	data := []byte{
		0xc2, 0x49, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	} // 2(h'010000000000000000')

	var v1 cbor.Tag
	err := cbor.Unmarshal(data, &v1)
	if err != nil {
		fmt.Printf("failed to unmarshal %x cbor.Tag: %s\n", data, err)
		return
	}

	em, _ := cbor.EncOptions{
		ByteSlice: cbor.ByteSliceToByteStringWithExpectedConversionToBase64URL,
	}.EncMode()
	b, err := em.Marshal(v1)
	if err != nil {
		fmt.Printf("failed to marshal: %s\n", err)
		return
	}

	var v2 interface{}
	err = cbor.Unmarshal(b, &v2)
	if err != nil {
		fmt.Printf("failed to unmarshal %x to interface{}: %s\n", b, err)
	}

	// Output:
	// failed to unmarshal c2d549010000000000000000 to interface{}: cbor: tag number 2 or 3 must be followed by byte string, got tag
}
```

**Expected**: The code snippet should produce valid CBOR data `2(h'010000000000000000')`.

**Got**: The code snippet produces invalid CBOR data `2(21(h'010000000000000000'))`.

cc: @benluddy

EDIT: s/malformed/invalid
