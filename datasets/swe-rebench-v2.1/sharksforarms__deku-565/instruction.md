Problems serializing signed values (negative values) in bitfields
When using signed types in bitfields I cannot serialize negative values (deserializing works).
With the example below I get `encode error: InvalidParam("bit size 16 of input is larger than bit requested size 10")`.

Any idea where to start? I suspect this can be solved maybe in library level (not in the macro?). Any hint is appreciated, then I could prepare a PR... **[HIDDEN]**
The error message ("input is larger than bit requested size") can clearly be allocated to a code location...

```rust
#[test]
fn check_signed_i10_decode_encode() {
    #[derive(Debug,PartialEq,Default,Clone,DekuRead,DekuWrite)]
    pub struct TestStruct {
        #[deku(bits="1")]
        pub a: bool,
        #[deku(pad_bits_before = "5", bits="10", endian = "big")]
        pub b: i16,
    }

    let buffer = vec![0b10000011,0b11111110];
    //                        ^^   ^^^^^^^^10 bits

    let ((remaining_bytes, offset), test_struct) = TestStruct::from_bytes((&buffer, 0)).expect("decoder error");
    // println!("{decoded_asterix:#?}");

    // everything consumed?
    assert_eq!(offset, 0);
    assert_eq!(remaining_bytes.len(), 0);

    // check content
    assert_eq!(test_struct.a, true);
    assert_eq!(test_struct.b, -2);

    // write back and check
    assert_eq!(buffer, test_struct.to_bytes().expect("encode error"))
}
```

### Additional contract requirements

- For a signed integer bitfield of width `n`, serialization must accept values in the signed `n`-bit range, from `-2^(n-1)` through `2^(n-1)-1`, and reject values outside that range. A serialized value must deserialize to the same value.
- For an unsigned integer bitfield of width `n`, serialization must accept values from `0` through `2^n-1` and reject values outside that range.
