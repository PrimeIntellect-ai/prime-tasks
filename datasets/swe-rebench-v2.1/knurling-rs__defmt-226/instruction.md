Corrupted stream with enum with 1 case
```rust
#[derive(defmt::Format)]
pub enum Payload {
    Number(u32),
}

let payload = Payload::Number(31337);
info!("print of death: {:?}", payload);
```

I guess it happens because the format string has no `|` char, so decoding doesn't expect the discriminator...?

### Additional contract requirements

- A single-variant enum (an enum with exactly one variant) must not encode a discriminant byte in its wire representation. Its encoding is the enum's format string index followed directly by the encoding of the variant's fields; for a unit variant that is just the format string index.
