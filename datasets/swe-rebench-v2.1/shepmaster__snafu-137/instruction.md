Multiple SNAFU attributes are not supported in one attribute
It is intended that we can say `#[snafu(a, b, c)]`, but it doesn't appear to work:

```rust
#[derive(Debug, Snafu)]
pub(crate) enum Error {
    #[snafu(visibility(pub(crate)), display("Moo"))]
    Alpha,
}
```

```
error: unexpected token
 --> tests/multi.rs:8:39
  |
8 |         #[snafu(visibility(pub(crate)), display("Moo"))]
  |                                       ^
```
