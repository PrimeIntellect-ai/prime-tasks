Support enumerations with generic lifetimes and types
e.g.

```rust
#[derive(Snafu)]
enum Error<'a, T> {
    InvalidUsername { name: &'a str, payload: T },
}
```

### Additional contract requirements

- The `Snafu` derive macro must accept enums that declare generic lifetime and type parameters, such as `enum Error<'a, T> { ... }`.
- For each variant, the derive provides a selector with a `fail<T>(self) -> Result<T, Error<...>>` method that returns the constructed variant wrapped in `Err`.
- `snafu::ResultExt::context` converts a lower-level error into the derived error variant, attaching the source, backtrace, and supplied context fields.
