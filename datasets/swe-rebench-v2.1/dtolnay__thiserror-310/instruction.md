Tuple Struct interior can't be accessed via .0.0
https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=ada5458f736b0dd393bbe31e10b4ff31

```rust
use thiserror::Error;

#[derive(Debug)]
pub struct S1(String);

#[derive(Debug)]
pub struct S2 {
    inner: String,
}

#[derive(Debug, Error)]
pub enum BigError {
    #[error("{:?}", .0)]
    E1(S1),
    #[error("{}", .0.inner)]
    E2(S2),

    #[error("{}", .0.0)]
    E3(S2),
}

fn main() {
}
```

E1 and E2 compile.
E3 fails to compile with

```
error: expected expression, found `.`
  --> src/main.rs:18:19
   |
18 |     #[error("{}", .0.0)]
   |                   ^ expected expression
```

I found it a bit surprising - it seems like it should work.

### Additional contract requirements

- Support chained tuple-field access such as `.0.0` in an error formatting expression when the value selected by `.0` is a tuple struct with a field at index 0. The `E3` example uses `S2`, which has a named field rather than a tuple field; the requested behavior applies when that field is tuple-shaped.
