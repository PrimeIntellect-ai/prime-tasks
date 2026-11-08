Support unit structure `struct S;` in derive-macro `DekuWrite`
We should support unit structure `struct S;` since `struct S {}` and `struct S();` are allowed to derive `DekuWrite`.
```rust
#[derive(DekuWrite)] // error: expected tuple struct or tuple variant, found unit struct `Zero`
#[deku(magic = b"\x00")]
struct Zero;
```
And `DekuRead` is no error here.

### Additional contract requirements

A unit struct declared without fields or a struct-level magic attribute must be accepted by `DekuWrite`; writing a value of that struct produces an empty byte vector. A unit struct with a struct-level magic attribute must write the configured magic bytes.
