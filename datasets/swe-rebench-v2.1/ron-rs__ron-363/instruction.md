Round-trip failure: ser -> de transforms Float(1.0) into Integer(1)
This example program probably ought to exit successfully
```rust
fn main() {
    let input = "1.0";
    let v: ron::Value = ron::from_str(input).unwrap();
    println!("{:?}", v);
    let ser = ron::to_string(&v).unwrap();
    println!("{:?}", ser);
    let roundtrip = ron::from_str(&ser).unwrap();
    println!("{:?}", roundtrip);
    assert_eq!(v, roundtrip);
}
```
But it doesn't:
```
Number(Float(Float(1.0)))
"1"
Number(Integer(1))
thread 'main' panicked at 'assertion failed: `(left == right)`
  left: `Number(Float(Float(1.0)))`,
 right: `Number(Integer(1))`', src/main.rs:9:5
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

This seems plausible as a ser/de behavior if RON only has a number type, but if that's the case `ron::Value::Number` should depend only on the numeric value not the discriminant.

### Additional contract requirements

- Parsing `1.0` as a `ron::Value`, serializing it, and deserializing the result must preserve equality with the parsed value.
- When serializing a floating-point value whose value is integral, emit a decimal suffix so that `1.0` serializes as `1.0`, not `1`, with both `to_string` and `to_string_pretty`.
