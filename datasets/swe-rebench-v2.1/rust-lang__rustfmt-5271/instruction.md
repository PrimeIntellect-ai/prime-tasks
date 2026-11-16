`#[rustfmt::skip::attributes(derive)]` not work.
```rust
    #[rustfmt::skip::attributes(derive)]
    #[allow(dead_code)]
    #[derive(StructField)]
    #[derive(Clone)]
    struct Struct {
        field: String,
    }
```

It will merge `#derive(StructField)` and `#[derive(Clone)]` to `#derive(StructField, Clone)]`, when i run `cargo fmt`.

I don't want to merge `#derive(StructField)` and `#[derive(Clone)]`.

### Additional contract requirements

When `merge_derives` is enabled, rustfmt must continue to merge separate derive attributes on items that do not have an applicable `#[rustfmt::skip::attributes(derive)]` directive.
