Duplicate comma with `trailing_comma = "Always"` in struct pattern
```rust
// src/main.rs
fn main() {
    let Foo { a, .. } = b;
}
```
```toml
# rustfmt.toml
edition = "2021"

unstable_features = true
trailing_comma = "Always"
```

Reformat with `rustfmt --config-path rustfmt.toml src/main.rs`

```rs
// src/main.rs
fn main() {
    let Foo { a,, .. } = b;
}
```

`rustfmt --version`: `rustfmt 1.4.38-nightly (4961b10 2021-11-04)`

### Additional contract requirements

Formatting a struct pattern that contains a `..` rest pattern with `trailing_comma = "Always"` must not emit a duplicate comma. For the reported input

```rust
fn main() {
    let Foo { a, .. } = b;
}
```

the formatted result must be `let Foo { a, .. } = b;` (a single comma separating `a` from `..`), not `let Foo { a,, .. } = b;`.
