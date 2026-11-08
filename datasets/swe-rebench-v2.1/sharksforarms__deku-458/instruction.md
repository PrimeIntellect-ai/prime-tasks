Support for fallible use cases for mutating and serializing fields
I was wondering if there was API support for either of the following use cases, or an equivalent thereof:

```rust
#[derive(Debug, Default, PartialEq, DekuWrite, DekuRead)]
#[deku(endian = "big")]
struct Test {
  #[deku(bits = 4)]
  field: u8,
}

fn fallible_case_1() -> anyhow::Result<()> {
  let mut x = Test::default();

  // Generated methods?
  x.set_field(17)?; // Fails
  x.set_field(15)?; // Ok

  Ok(())
}

fn fallible_case_2() -> anyhow::Result<()> {
  let mut x = Test::default();
  x.field = 17;
  x.to_bytes()?; // Does not error, alarmingly
  x.to_bytes_checked()?; // Errors because 17 >= 16; is there something like this?
  Ok(())
}
```

### Additional contract requirements

- Serializing a struct with `to_bytes()` must return an error when a field's value does not fit within the bit size declared by `#[deku(bits = ...)]`, instead of silently truncating the value.
- The error returned in that case is `DekuError::InvalidParam`.
