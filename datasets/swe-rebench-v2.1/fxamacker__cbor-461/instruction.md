bug: updated fuzzing detected panic while decoding CBOR nil or CBOR undefined to `*cbor.SimpleValue`
Decoding CBOR nil or CBOR undefined to `*cbor.SimpleValue` panics.

This crash bug was detected while adding more tests and updating fuzzer.

As mentioned in docs for `cbor.Unmarshal`, decoding CBOR nil or CBOR undefined to any Go pointer value should reset the pointer to nil.

```
// To unmarshal CBOR into a pointer, Unmarshal sets the pointer to nil
// if CBOR data is null (0xf6) or undefined (0xf7).  Otherwise, Unmarshal
// unmarshals CBOR into the value pointed to by the pointer.  If the
// pointer is nil, Unmarshal creates a new value for it to point to.
```
