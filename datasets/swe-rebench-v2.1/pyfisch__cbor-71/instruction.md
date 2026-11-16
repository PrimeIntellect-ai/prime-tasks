deserializing big byte arrays using `from_reader` does not round-trip
```rust
extern crate serde_cbor;
extern crate serde_bytes;

use std::io::Cursor;
use serde_bytes::ByteBuf;

fn main() {
    let input = ByteBuf::from(vec![0u8; 2048 * 1024]);
    let cbor = serde_cbor::to_vec(&input).unwrap();
    let output: ByteBuf = serde_cbor::from_reader(Cursor::new(cbor.as_slice())).unwrap();
    assert_eq!(input.len(), output.len());
}
```

I would expect `input` and `output` to have the same length, but instead `output` is only 16KiB long.
It works fine though using `serde_cbor::from_slice` instead of `serde_cbor::from_reader`.
