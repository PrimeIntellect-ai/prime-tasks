Range for standard number types
Is there a reason, why no default minimum and maximum values are generated with schema_for! for rust built-in number types, like i8-i128, u8-u128, isize, usize, f32, f64?

### Additional contract requirements

- Generated schemas for `i8`, `i16`, `u8`, and `u16` must include inclusive `minimum` and `maximum` constraints equal to the full representable range of the Rust type.
- Floating-point types (`f32` and `f64`) are outside the scope of this range requirement.
