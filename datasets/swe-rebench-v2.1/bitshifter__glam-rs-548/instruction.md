lerp()'s implementation has a loss of precision when inputs span multiple orders of magnitude
The general implementation of `lerp` in glam for floating point types takes the form as follows:

```rust
fn lerp(a: Self, b: Self, t: f32) -> Self {
  a + (b - a) * t
}
```

However, this presents floating point precision issues if `a` and `b` have very different exponent values due to the `(b - a)` in the computation. You can test this via `lerp(-16.0e30, 16.0, 1.0)` returning 0.0 instead of the correct 16.0. It may be more accurate to use the following form:

```rust
fn lerp(a: Self, b: Self, t: f32) -> Self {
  [HIDDEN]
}
```

This may not be a significant regression in performance as floating point multiplication is generally much faster than addition.

### Additional contract requirements

- Floating-point `lerp` must avoid precision loss when endpoints differ greatly in magnitude; in particular, `lerp(-16.0e30, 16.0, 1.0)` must return the destination value `16.0`.
