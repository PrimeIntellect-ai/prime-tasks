const-oid: panic unexpected, parser bugs
`ObjectIdentifier::new` should return Err with invalid data, but returns Ok.

Then, `Display::fmt` panics at `const-oid/src/lib.rs:257`.

```toml
# bug exists in 0.9.5 also
const_oid = { version = "0.10.0-rc.2" }
```

```rust
#[test]
fn test_oid_arc() {
    // Result<ObjectIdentifier>
    // return Ok(..)
    let oid = ObjectIdentifier::new("1.2.840.10045.4.3.4.1111111111");

    // prints oid: Ok(ObjectIdentifier(
    println!("oid: {oid:?}");
    // panics: OID malformed: ArcTooBig
    // const-oid/src/arcs.rs:116:25
}
```

### Additional contract requirements

An individual numeric arc greater than `u32::MAX` is outside the range supported by `ObjectIdentifier`, so `ObjectIdentifier::new` must return an error instead of constructing an object. The cited input `1.2.840.10045.4.3.4.1111111111` is valid and within that range, so parsing it must succeed; handling or formatting its result must not panic.
