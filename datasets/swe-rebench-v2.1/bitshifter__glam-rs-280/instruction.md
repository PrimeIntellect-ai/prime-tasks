Wrong determinant calculation for `Mat4`
This test case fails:

```rust
#[test]
fn test_determinant() {
    use glam::{Mat4, Vec4};
    let matrix = Mat4::from_cols(
        Vec4::new(0.0, 0.0, 0.0, 1.0),
        Vec4::new(1.0, 0.0, 0.0, 0.0),
        Vec4::new(0.0, 0.0, 1.0, 0.0),
        Vec4::new(0.0, 1.0, 0.0, 0.0),
    );
    assert_eq!(matrix.determinant(), 1.0);
}
```

The result of the determinant calculation in glam is `0.0`, while it should be `1.0`.
