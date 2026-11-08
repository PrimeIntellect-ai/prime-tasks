bool false RLP encoding should match u8
[Version 0.5.0 of the rlp crate](https://docs.rs/rlp/0.5.0/rlp/) encodes false to 0x00, but u8 (byte) zero to 0x80.

The [RLP library in Geth](https://github.com/ethereum/go-ethereum/blob/master/rlp/decode.go#L41) expects 0x80 for `false`, and produces this error:

```
rlp: non-canonical integer (leading zero bytes) for bool
```

This is how it behaves today:

```rust
    #[test]
    fn encode_false() {
        #[derive(rlp_derive::RlpEncodable)]
        struct MeHasBool {
            flag: bool,
        }

        assert_eq!(*rlp::encode(&MeHasBool { flag: false }), [0xC1, 0x00]);
    }

    #[test]
    fn encode_zero_byte() {
        #[derive(rlp_derive::RlpEncodable)]
        struct MeHasByte {
            flag: u8,
        }

        assert_eq!(*rlp::encode(&MeHasByte { flag: 0 }), [0xC1, 0x80]);
    }
```

I'd expect both encodings match.

Note: the tests above also use [rlp-derive 0.1.0](https://docs.rs/rlp-derive/0.1.0/rlp_derive/)
